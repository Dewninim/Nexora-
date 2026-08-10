"""
Nuromathix Backend — Flask API  (Model 2 build)
Model 1 : Random Forest difficulty score 1-5 per chunk
Model 2 : Prompt-engineered adaptive question generator (Gemini 1.5 Flash)
          - mixes easy (fill-blank) / medium (short-answer) / hard (4-part problem)
          - prioritises chunks using Model 1's per-chunk difficulty + weak topics
          - progressive 10-level contextual hints (generated on request)
          - per-question timing, timeout/overtime tracking
XAI     : Full step-by-step explanation per answer (all formats) via Gemini —
          free-text grading isn't a fixed-feature classifier, so SHAP does
          not apply there. Model 1's difficulty score IS a real classifier
          (RandomForest over TF-IDF features), so THAT prediction gets real
          SHAP (TreeExplainer) feature-attribution explanations below.
Curve   : Ebbinghaus R(t)=e^(-t/S) forgetting curve, paced by study mode
"""
import os,json,uuid,math,pickle,re,logging,random
from datetime import datetime,timedelta

# Must run BEFORE `import fitz` below — PyMuPDF's bundled OCR engine reads
# TESSDATA_PREFIX when the module loads, not per-call, so setting it after
# import has no effect (confirmed: setting it post-import still produced
# "TESSDATA_PREFIX not set" from PyMuPDF's OCR, even though os.environ had
# it correctly set by that point).
if not os.environ.get("TESSDATA_PREFIX"):
    for _c in ["/usr/share/tesseract-ocr/5/tessdata","/usr/share/tesseract-ocr/4.00/tessdata",
        "/usr/share/tessdata","/usr/local/share/tessdata",
        "/opt/homebrew/share/tessdata","/usr/local/opt/tesseract/share/tessdata",
        r"C:\Program Files\Tesseract-OCR\tessdata",r"C:\Program Files (x86)\Tesseract-OCR\tessdata"]:
        if os.path.isdir(_c):
            os.environ["TESSDATA_PREFIX"]=_c
            break

from flask import Flask,request,jsonify
from flask_cors import CORS
from dotenv import load_dotenv
from pymongo import MongoClient
from pymongo.errors import PyMongoError
import fitz
import urllib.request,urllib.error

load_dotenv()  # reads backend/.env if present (never commit this file)

logging.basicConfig(level=logging.INFO)
log=logging.getLogger(__name__)
app=Flask(__name__)
CORS(app)

# ── Session storage: MongoDB, with in-memory fallback ─────────────────────────
MONGO_URI=os.environ.get("MONGO_URI","mongodb://localhost:27017")
MONGO_DB_NAME=os.environ.get("MONGO_DB_NAME","neuromathix")

_sessions_col=None
_materials_col=None
_memory_sessions:dict={}
_memory_materials:dict={}

try:
    _client=MongoClient(MONGO_URI,serverSelectionTimeoutMS=3000)
    _client.admin.command("ping")
    _sessions_col=_client[MONGO_DB_NAME]["sessions"]
    _materials_col=_client[MONGO_DB_NAME]["materials"]
    log.info("[OK] Connected to MongoDB at %s (db=%s)",MONGO_URI,MONGO_DB_NAME)
except PyMongoError as e:
    log.warning("[WARN] MongoDB not reachable (%s). Falling back to in-memory storage.",e)

def _session_get(sid):
    if _sessions_col is not None:
        return _sessions_col.find_one({"_id":sid})
    return _memory_sessions.get(sid)

def _session_save(sid,doc):
    doc["_id"]=sid
    if _sessions_col is not None:
        _sessions_col.replace_one({"_id":sid},doc,upsert=True)
    else:
        _memory_sessions[sid]=doc

def _session_update(sid,updates):
    if _sessions_col is not None:
        _sessions_col.update_one({"_id":sid},{"$set":updates})
    else:
        _memory_sessions.setdefault(sid,{}).update(updates)

def _session_exists(sid):
    return _session_get(sid) is not None

def _sessions_for_material(material_id):
    if _sessions_col is not None:
        return list(_sessions_col.find({"material_id":material_id}).sort("session_number",1))
    return sorted([s for s in _memory_sessions.values() if s.get("material_id")==material_id],
        key=lambda s:s.get("session_number",0))

# ── Materials: the uploaded PDF itself, persisted once under the user's
#    profile. A user can start any number of sessions (quiz attempts) against
#    the same material without re-uploading — this is what actually makes
#    "session 2 adapts to session 1" possible, since both sessions now share
#    one material_id and one chunk_coverage tracker. ──
def _material_get(mid):
    if _materials_col is not None:
        return _materials_col.find_one({"_id":mid})
    return _memory_materials.get(mid)

def _material_save(mid,doc):
    doc["_id"]=mid
    if _materials_col is not None:
        _materials_col.replace_one({"_id":mid},doc,upsert=True)
    else:
        _memory_materials[mid]=doc

def _material_update(mid,updates):
    if _materials_col is not None:
        _materials_col.update_one({"_id":mid},{"$set":updates})
    else:
        _memory_materials.setdefault(mid,{}).update(updates)

def _material_exists(mid):
    return _material_get(mid) is not None

def _materials_for_user(user_id):
    if _materials_col is not None:
        return list(_materials_col.find({"user_id":user_id}).sort("uploaded_at",-1))
    return sorted([m for m in _memory_materials.values() if m.get("user_id")==user_id],
        key=lambda m:m.get("uploaded_at",""),reverse=True)

GEMINI_API_KEY=os.environ.get("GEMINI_API_KEY","")
# NOTE: gemini-1.5-flash was retired by Google and returns 404 for every call —
# every question/hint/XAI request was silently falling through to the offline
# fallback generator. gemini-3.6-flash is the current GA flash-tier model.
GEMINI_URL=f"https://generativelanguage.googleapis.com/v1beta/models/gemini-3.6-flash:generateContent?key={GEMINI_API_KEY}"
GEMINI_WORKS=False if not GEMINI_API_KEY else None
_GEMINI_COOLDOWN_UNTIL=0.0  # epoch seconds; while now < this, skip Gemini entirely rather than guarantee another 429
if not GEMINI_API_KEY:
    log.warning("[WARN] GEMINI_API_KEY not set — using local fallback generator/hints, not Gemini.")

MODEL1_RF=None;MODEL1_VEC=None;MODEL_INFO=None
try:
    with open("model1_random_forest.pkl","rb") as f: MODEL1_RF=pickle.load(f)
    with open("model1_vectorizer.pkl","rb") as f: MODEL1_VEC=pickle.load(f)
    try:
        with open("model_info.pkl","rb") as f: MODEL_INFO=pickle.load(f)
    except:pass
    log.info("[OK] Model 1 loaded classes=%s",MODEL1_RF.classes_.tolist())
except Exception as e:
    log.warning("[WARN] Model 1 not found: %s",e)

# Real SHAP explainability for Model 1's difficulty classifier — TreeExplainer
# is exact (no sampling) for tree ensembles and needs no background dataset,
# so it's built once here and reused for every chunk instead of per-call.
MODEL1_SHAP_EXPLAINER=None
try:
    import shap as _shap
    if MODEL1_RF is not None:
        MODEL1_SHAP_EXPLAINER=_shap.TreeExplainer(MODEL1_RF)
        log.info("[OK] SHAP TreeExplainer ready for Model 1")
except Exception as e:
    log.warning("[WARN] SHAP unavailable — difficulty predictions will skip feature-attribution explanations: %s",e)

# Small standard English stopword list — filters function words (the, of,
# how, ...) out of SHAP's top features so what's surfaced is actual
# math/content vocabulary, not grammar. Not model output, just a fixed
# linguistic list (same role nltk.corpus.stopwords would play).
_STOPWORDS={"the","a","an","of","in","on","at","to","for","and","or","but","is","are","was",
    "were","be","been","being","this","that","these","those","it","its","as","by","with",
    "from","we","you","your","our","their","his","her","he","she","they","i","if","then",
    "than","so","not","no","do","does","did","can","could","should","would","will","shall",
    "may","might","must","have","has","had","which","what","who","whom","how","when","where",
    "why","each","every","any","some","all","both","either","neither","such","also","just",
    "up","down","out","over","under","again","further","once","here","there","one","two",
    "into","about","above","below","between","after","before"}

def explain_difficulty(text,predicted_class,top_n=5):
    """Real SHAP feature-attribution explanation for a Model 1 difficulty
    prediction — which words in THIS chunk pushed the RandomForest toward
    the class it actually predicted. Returns [] if SHAP or Model 1 aren't
    available (heuristic-fallback predictions have no such explanation to
    give, since there's no model to attribute)."""
    if MODEL1_SHAP_EXPLAINER is None or MODEL1_VEC is None or MODEL1_RF is None:
        return []
    try:
        X=MODEL1_VEC.transform([text]).toarray().astype("float64")
        sv=MODEL1_SHAP_EXPLAINER.shap_values(X,check_additivity=False)
        class_idx=list(MODEL1_RF.classes_).index(predicted_class)
        # shap>=0.45 returns shape (n_samples, n_features, n_classes) for
        # multiclass tree models; older versions return a list of per-class
        # arrays instead — handle both so a shap version bump doesn't break this.
        if isinstance(sv,list):
            values=sv[class_idx][0]
        else:
            values=sv[0,:,class_idx]
        names=MODEL1_VEC.get_feature_names_out()
        ranked=sorted(range(len(values)),key=lambda i:-abs(values[i]))
        out=[]
        for i in ranked:
            word=names[i]
            if values[i]==0 or word in _STOPWORDS or word.isdigit():continue
            out.append({"word":word,"contribution":round(float(values[i]),4),
                "direction":"increases" if values[i]>0 else "decreases"})
            if len(out)>=top_n:break
        return out
    except Exception as e:
        log.warning("[explain_difficulty] SHAP failed: %s",e)
        return []

DLVL={1:"very_easy",2:"easy",3:"medium",4:"hard",5:"very_hard"}

# ══════════════════════════════════════════════════════════════════════════════
# CONFIG — question mix, timing, session pacing
# ══════════════════════════════════════════════════════════════════════════════
MIN_QUESTIONS=20
MAX_QUESTIONS=50
TIME_ALLOTMENT={"easy":90,"medium":150,"hard":480}   # seconds per format
MAX_HINT_LEVEL=10
MASTERY_MAX_SESSIONS=8       # "until mastery" mode never plans more than this
MASTERY_MIN_GAP_DAYS=1
MASTERY_MAX_GAP_DAYS=14      # never lets a gap balloon into months/years
FIXED_MODE_MAX_GAP_DAYS=14
SESSION_TIME_BUDGET_SECONDS=2700   # ~45 min target ceiling for one sitting

MATH_KEYWORDS={"equation","equations","theorem","proof","integral","integrals","derivative",
    "derivatives","matrix","matrices","vector","vectors","polynomial","calculus","algebra",
    "geometry","probability","function","functions","variable","variables","coefficient",
    "limit","limits","differential","summation","formula","formulas","solve","solution",
    "root","roots","graph","axis","angle","triangle","vertex","slope","logarithm","exponent",
    "factorial","determinant","eigenvalue","statistics","distribution","mean","variance",
    "convergence","iteration","interval","numerical","approximation","theorem","hypothesis"}
MATH_SYMBOLS=set("+-*/=^√∫∑∞≤≥±×÷π∂∇∆θαβγλμσ")
MATH_SCORE_THRESHOLD=0.55   # heuristic; tune if false positives/negatives appear

def is_math_document(full_text):
    """Heuristic math-subject gate, run before Model 1. No ML training data
    needed — combines math keyword density, math symbol density, and digit
    density. Not perfect; logs its raw score so the threshold can be tuned."""
    text=full_text.lower()
    words=re.findall(r"[a-zA-Z]+",text)
    total_words=max(len(words),1)
    kw_hits=sum(1 for w in words if w in MATH_KEYWORDS)
    kw_ratio=kw_hits/total_words
    symbol_hits=sum(full_text.count(s) for s in MATH_SYMBOLS)
    symbol_density=symbol_hits/max(len(full_text),1)
    digit_ratio=sum(c.isdigit() for c in full_text)/max(len(full_text),1)
    score=(kw_ratio*40)+(symbol_density*300)+(digit_ratio*15)
    is_math=score>=MATH_SCORE_THRESHOLD
    confidence=round(min(1.0,score/2.0),3)
    reason=f"keyword_ratio={kw_ratio:.4f} symbol_density={symbol_density:.5f} digit_ratio={digit_ratio:.4f} raw_score={score:.3f} threshold={MATH_SCORE_THRESHOLD}"
    return is_math,confidence,reason

_OCR_AVAILABLE=None  # None=untested, True/False=cached after first real attempt

def _ocr_page_text(page):
    """Attempts OCR on a single page via PyMuPDF's built-in Tesseract
    integration. Returns '' on any failure (missing Tesseract binary,
    missing language data, etc.) rather than raising — OCR is a best-effort
    enhancement, not something that should crash an upload."""
    global _OCR_AVAILABLE
    if _OCR_AVAILABLE is False:
        return ""
    try:
        tp=page.get_textpage_ocr(flags=0,dpi=200,full=True)
        txt=page.get_text(textpage=tp)
        _OCR_AVAILABLE=True
        return txt
    except Exception as e:
        if _OCR_AVAILABLE is None:
            log.warning("[extract_chunks] OCR unavailable (%s) — scanned/image-only pages "
                "will be skipped instead of read. Install Tesseract OCR "
                "(https://github.com/UB-Mannheim/tesseract/wiki for Windows, "
                "'apt install tesseract-ocr' for Linux) to enable it.",e)
        _OCR_AVAILABLE=False
        return ""

def extract_chunks(pdf_bytes,wpc=300,max_chunks=40):
    doc=fitz.open(stream=pdf_bytes,filetype="pdf")
    page_texts=[]
    ocr_used_on=0;ocr_attempts=0
    MAX_OCR_PAGES=20  # OCR is slow (real per-page cost) — an unbounded loop
                       # over a large scanned document could take minutes and
                       # blow well past the frontend's upload timeout. Capping
                       # this keeps worst-case upload latency bounded; any
                       # pages beyond the cap just contribute no text, same
                       # as before OCR support existed.
    for p in doc:
        t=p.get_text()
        # A page with a real text layer but under ~20 chars is almost
        # certainly a scanned/image page (maybe just a stray page number) —
        # try OCR on it instead of silently contributing nothing.
        if len(t.strip())<20 and ocr_attempts<MAX_OCR_PAGES:
            ocr_attempts+=1
            ocr_t=_ocr_page_text(p)
            if len(ocr_t.strip())>len(t.strip()):
                t=ocr_t;ocr_used_on+=1
        page_texts.append(t)
    if ocr_attempts:
        log.info("[extract_chunks] OCR attempted on %d pages, recovered text from %d of them%s",
            ocr_attempts,ocr_used_on," (hit the %d-page OCR cap — some later scanned pages were skipped for speed)"%MAX_OCR_PAGES if ocr_attempts>=MAX_OCR_PAGES else "")

    # Drop whole TOC/index/front-matter PAGES before merging into 300-word
    # chunks — checking density on the final merged chunk (below) misses a
    # short Contents page once it's diluted by surrounding real content in
    # the same window. A standalone page is small enough that its own
    # marker density stays high and gets caught here instead.
    dropped_pages=0
    for i,pt in enumerate(page_texts):
        if pt.strip() and (_is_toc_like(pt) or _is_frontmatter_like(pt)):
            page_texts[i]="";dropped_pages+=1
    if dropped_pages:
        log.info("[extract_chunks] dropped %d whole page(s) as TOC/index/front-matter before chunking",dropped_pages)

    text=" ".join(page_texts)
    words=text.split();out=[];dropped_toc=0;dropped_frontmatter=0
    for i in range(0,len(words),wpc):
        c=" ".join(words[i:i+wpc]).strip()
        if len(c)<=60:continue
        if _is_toc_like(c):dropped_toc+=1;continue
        if _is_frontmatter_like(c):dropped_frontmatter+=1;continue
        out.append(c)
    log.info("[extract_chunks] kept %d chunks, dropped %d as TOC-like, %d as front-matter/marketing-like",
        len(out),dropped_toc,dropped_frontmatter)
    if not out:
        # Whole document looked like TOC/reference matter or pure front
        # matter — better to proceed with something than reject outright;
        # fall back to unfiltered chunks.
        log.warning("[extract_chunks] every chunk looked like TOC/index or front-matter text — using unfiltered chunks")
        for i in range(0,len(words),wpc):
            c=" ".join(words[i:i+wpc]).strip()
            if len(c)>60:out.append(c)
    return out[:max_chunks],text

def _is_frontmatter_like(text):
    """Detects preface / motivation / acknowledgments / dedication /
    about-the-author prose, contest/promo blurbs, and other non-math
    front-matter. This is real content, but NOT mathematical instructional
    content — it should never become a question source.

    Split into two tiers after a real failure: a sentence containing the
    literal word "preface" and a website domain (".org") was still getting
    through because a single stray "/" (from "AMC 10/12") pushed the old
    single-threshold math-density check just over the cutoff. STRONG
    markers — no legitimate math-instructional sentence organically
    contains these — flag unconditionally. WEAK markers remain gated by
    density, since those phrases could in principle appear in real prose.

    v3 fix: ".org"/".com"/"www." were promoted to unconditional strong
    markers to catch a scraped course-marketing page — but in real testing
    this caused EVERY chunk in a document to be rejected (0/63 kept),
    because the source PDF has "OmegaLearn.org" printed as a running page
    footer/watermark on every page. A domain mention alone says nothing
    about whether the surrounding content is real math or not — it only
    becomes real evidence of junk when it's clearly part of marketing
    prose (a full phrase like "visit us at X.org" or "OmegaLearn.org
    Preface"), not a bare watermark fragment. Domains are now WEAK
    (density-gated) evidence, same as the other phrases that could
    legitimately appear incidentally."""
    tl=text.lower()
    strong=["preface","acknowledg","dedicat","foreword","copyright","all rights reserved",
        "about the author","table of contents","list of topics",
        "raffle","giveaway","prize","enter to win","win a","brilliant premium",
        "sign up","register now","subscribe","newsletter","free trial"]
    if any(kw in tl for kw in strong):
        return True
    weak=["motivation","about this book","this book was","we hope you","our passion",
        "thank you for","special thanks",".org",".com","www."]
    if not any(kw in tl for kw in weak):
        return False
    math_signals=len(re.findall(r"[=+\-*/^]|\d+\.\d+|\\frac|\\int|\\sum|\bsolve\b|\bequation\b|\bformula\b",text,re.IGNORECASE))
    word_count=max(len(text.split()),1)
    return (math_signals/word_count)<0.05

def _has_real_math_evidence(text):
    """The actual structural fix, not another blacklist entry. Instead of
    trying to enumerate every possible non-math phrasing a scraped/
    promotional PDF might contain (provably unwinnable — three unrelated
    junk phrasings have already been found: book preface, course-marketing
    webpage, contest raffle), this requires POSITIVE proof of genuine
    mathematical working before a chunk is allowed as a question source at
    all. A chunk with no numeric computation, no formula, no equation-like
    pattern anywhere in it is not math content, regardless of what words it
    does or doesn't contain."""
    real_math_signals=len(re.findall(
        r"\d\s*[=+\-*/^]\s*-?\d|=\s*-?\d+(\.\d+)?|\\frac|\\int|\\sum|\\sqrt|"
        r"\d+\s*[a-zA-Z]\^?\d*|\btheorem\b|\bproof\b|\bsolve\b.{0,40}=|"
        r"\bformula\b.{0,30}=|\bequation\b.{0,30}=",
        text))
    word_count=max(len(text.split()),1)
    return(real_math_signals/word_count)>=0.008

def _is_toc_like(text):
    """Detects table-of-contents / index / 'answers to exercises' listing
    pages so they're skipped before question generation. These pages are
    dense with unit/section markers and page-count parentheticals but have
    almost no real explanatory sentences — blanking a word from them
    produces meaningless questions."""
    markers=0
    markers+=len(re.findall(r"\bUNIT\s+\d",text,re.IGNORECASE))
    markers+=text.count("Exercises")
    markers+=len(re.findall(r"Answers to",text,re.IGNORECASE))
    markers+=len(re.findall(r"\b\d+\.\d+\b",text))          # section numbers: 9.1, 9.2, ...
    markers+=len(re.findall(r"\(\d+\s*pages?\)",text,re.IGNORECASE))  # "(9 pages)"
    # OCR-mangled dotted-leader TOC lines lose the spaces/dots between a
    # chapter title and its page number — "Area under a curve .... 149"
    # becomes "Areaundercurve149". A lowercase word glued directly to a
    # trailing page number like that essentially never happens in real
    # prose, so weight it heavily — this is what actually catches a TOC
    # page whose OCR quality was too poor for the marker patterns above.
    markers+=len(re.findall(r"\b[a-z]{5,}\d{1,3}\b",text))*3
    word_count=max(len(text.split()),1)
    density=markers/word_count
    return density>0.10   # tuned threshold — TOC pages score far above this

def predict_difficulty(text,explain=False):
    """explain=True additionally runs real SHAP attribution for this
    prediction (see explain_difficulty()) — off by default since it's a
    real per-call cost (~0.1-1s), so callers processing many chunks should
    only request it for a bounded subset."""
    if MODEL1_RF and MODEL1_VEC:
        try:
            X=MODEL1_VEC.transform([text])
            score=int(MODEL1_RF.predict(X)[0])
            proba=MODEL1_RF.predict_proba(X)[0].tolist()
            out={"score":score,"level":DLVL.get(score,"medium"),"confidence":round(float(max(proba)),3),"source":"model1_rf"}
            if explain:
                out["shap_top_features"]=explain_difficulty(text,score)
            return out
        except Exception as e:log.warning("M1 err:%s",e)
    words=text.split();avg=sum(len(w) for w in words)/max(len(words),1)
    s=min(5,max(1,round(avg-1)))
    return{"score":s,"level":DLVL.get(s,"medium"),"confidence":0.55,"source":"heuristic"}

# ══════════════════════════════════════════════════════════════════════════════
# MODEL 2 — chunk prioritisation + question-mix planning
# ══════════════════════════════════════════════════════════════════════════════
def determine_question_count(num_chunks):
    return max(MIN_QUESTIONS,min(MAX_QUESTIONS,num_chunks*2))

def determine_type_mix(profile):
    """Returns (easy_ratio, medium_ratio, hard_ratio). Uses accuracy_by_type
    and overtime patterns from a PRIOR session if available, else falls back
    to the same struggling/steady/excelling read used for difficulty.
    A first-ever session (no answer history) always gets the neutral mix —
    zero mistakes from zero data is not the same signal as zero mistakes
    from real answers, and defaulting to 'excelling' there would hand a
    brand-new student the hardest mix on their very first session."""
    if not profile.get("has_history",True):
        return 0.35,0.35,0.30
    acc=profile.get("accuracy_by_type") or {}
    mr=profile.get("mistake_rate",0.5);hr=profile.get("hint_press_rate",0.0)
    easy_acc=acc.get("easy");hard_acc=acc.get("hard")
    if mr>0.60 or hr>0.70:
        return 0.55,0.30,0.15
    if mr<0.20 and hr<0.20 and (hard_acc is None or hard_acc>=0.7):
        return 0.20,0.35,0.45
    if hard_acc is not None and hard_acc<0.3:
        return 0.45,0.35,0.20   # hard-type was rough last time, pull back
    if easy_acc is not None and easy_acc>=0.9:
        return 0.20,0.40,0.40   # easy is trivial for them, shift up
    return 0.35,0.35,0.30

def _weighted_chunk_order(chunks,profile):
    """Chunks are repeated proportionally to (a) Model 1 difficulty score and
    (b) whether their content touches a topic in the student's mistake_patterns,
    so question generation is drawn more often from the parts that matter.
    Used only as a fallback when no coverage data exists yet."""
    weak_topics={t.lower() for t in profile.get("mistake_patterns",[])}
    weighted=[]
    for c in chunks:
        w=c["difficulty"]["score"]
        if weak_topics and any(t in c["text"].lower() for t in weak_topics):
            w+=2
        weighted.extend([c]*max(1,w))
    random.shuffle(weighted)
    return weighted

def _coverage_aware_chunk_order(chunks,coverage,profile):
    """Primary chunk-selection strategy: chunks NEVER asked about yet always
    come first (so one pass through enough sessions touches the whole
    document), then chunks used the fewest times, then — among equally
    covered chunks — higher Model1 difficulty and weak-topic matches are
    preferred. This is what makes 'the session should cover all content'
    actually true across a multi-session study plan instead of the same
    weighted-random subset getting drawn every time."""
    weak_topics={t.lower() for t in profile.get("mistake_patterns",[])}
    def sort_key(c):
        used=coverage.get(str(c["index"]),0)
        weak_bonus=1 if(weak_topics and any(t in c["text"].lower() for t in weak_topics))else 0
        return(used,-c["difficulty"]["score"]-weak_bonus)
    return sorted(chunks,key=sort_key)

def _distribute_counts(total,easy_r,med_r,hard_r):
    e=round(total*easy_r);m=round(total*med_r);h=total-e-m
    if h<0:h=0;m=total-e
    return e,m,h

def _cap_to_time_budget(easy_n,med_n,hard_n,budget=SESSION_TIME_BUDGET_SECONDS):
    """Trims the mix so estimated total time fits one reasonable sitting.
    Hard (multi-part) questions are the most expensive, so they're trimmed
    first, then medium, keeping at least a few of each where possible."""
    def total_time(e,m,h):
        return e*TIME_ALLOTMENT["easy"]+m*TIME_ALLOTMENT["medium"]+h*TIME_ALLOTMENT["hard"]
    e,m,h=easy_n,med_n,hard_n
    while total_time(e,m,h)>budget and h>3:
        h-=1
    while total_time(e,m,h)>budget and m>3:
        m-=1
    while total_time(e,m,h)>budget and e>3:
        e-=1
    return e,m,h

# ══════════════════════════════════════════════════════════════════════════════
# MODEL 2 — Gemini prompt builders
# ══════════════════════════════════════════════════════════════════════════════
def build_model2_system_prompt(p,easy_n,med_n,hard_n):
    avg=p.get("avg_difficulty_score",3);hr=p.get("hint_press_rate",0.0)
    mr=p.get("mistake_rate",0.5);pace=p.get("preferred_pace","medium")
    pats=p.get("mistake_patterns",[]);sc=p.get("session_count",1);avgt=p.get("avg_time_seconds",35)
    acc=p.get("accuracy_by_type") or {}
    if mr>0.60 or hr>0.70:
        nd=max(1,avg-1);an="STRUGGLING: simplify language, add context clues, make distractors clearly distinct."
    elif mr<0.20 and hr<0.20:
        nd=min(5,avg+1);an="EXCELLING: increase depth, multi-step reasoning, precise terminology, subtle distractors."
    else:
        nd=avg;an="STEADY: maintain difficulty, mix straightforward and moderate questions."
    nl=DLVL.get(nd,"medium")
    weak_list=pats[:3]
    pn=f"\nWEAK TOPICS (this student's actual recurring mistakes): {', '.join(weak_list)}." if weak_list else "\nWEAK TOPICS: none recorded yet (first session or clean history) — treat every topic as untested."
    accn=f"\nLAST-SESSION ACCURACY BY TYPE: easy={acc.get('easy')}, medium={acc.get('medium')}, hard={acc.get('hard')}." if acc else ""
    total_q=easy_n+med_n+hard_n

    return f"""You are Model 2 — the adaptive learning engine for Nuromathix, a maths platform.
Model 2 is not just a question generator: you own the full personalized-assessment
decision, from reading this student's behavioural profile through to producing the
actual session content. Do all of the following correctly, not just some of it:

══════════════════════════════════════════════════════════════════════════════
1. STUDENT BEHAVIOUR PROFILE (already analysed upstream — use it, don't ignore it)
══════════════════════════════════════════════════════════════════════════════
Current difficulty : {avg}/5 ({DLVL.get(avg,'medium')})
Next difficulty     : {nd}/5 ({nl})
Hint usage rate     : {hr:.0%}
Mistake rate        : {mr:.0%}
Avg time/question   : {avgt:.0f}s
Preferred pace      : {pace}
Sessions done       : {sc}{pn}{accn}

ADAPTATION DECISION: {an}

══════════════════════════════════════════════════════════════════════════════
2. WEAK/IMPROVING/MAINTENANCE ALLOCATION (mandatory — this is not optional flavour)
══════════════════════════════════════════════════════════════════════════════
Split the {total_q} questions across the CHUNKS using this ratio, based on the
WEAK TOPICS list above:
- ~70% of questions target chunks whose topic matches a WEAK TOPIC, or — if there
  are no recorded weak topics yet — target the highest Model1-difficulty chunks
  (the student hasn't been tested on them, so treat "untested" as the priority).
- ~20% target topics the student got partially right last session (accuracy
  40-80% in LAST-SESSION ACCURACY BY TYPE) — reinforcing topics in progress.
- ~10% target topics the student is already strong in (accuracy >80%), purely
  to maintain retention, not to teach something new.
This is a real instruction, not a suggestion: if you generate every question from
the same one or two chunks and ignore this split, you have failed the task.

══════════════════════════════════════════════════════════════════════════════
3. MATERIAL UNDERSTANDING — this is a MATHEMATICS platform
══════════════════════════════════════════════════════════════════════════════
Every question — including "easy" ones — must require the student to perform or
recall an actual mathematical step: evaluate a formula at given values, identify
the next value in an iterative sequence, compute a derivative/integral/root/
result, or apply a rule from the passage to a new (but similar) case. NEVER
produce a question that just blanks out a random vocabulary word from a
sentence — that tests reading comprehension, not mathematics, and is an
automatic failure regardless of how the rest of the output looks.

Do the actual arithmetic yourself before writing "expected_answer" or
"correct_index" — every numeric answer must be independently verifiable by
redoing the computation shown in "xai_explanation". A wrong computed answer is
worse than a slightly-too-easy question.

GRADE/LEVEL: the source material will usually NOT state its grade level or
target audience explicitly. Infer it yourself from the vocabulary, notation,
and complexity of the CHUNKS below (e.g. basic arithmetic/ratios reads as
lower-secondary; derivatives, matrices, or proofs read as upper-secondary or
early undergraduate) and keep every generated question consistent with that
same inferred level — don't drift into harder or easier territory than the
source material itself demonstrates.

FORMATTING: this app renders PLAIN TEXT, not LaTeX. Never wrap any
expression in $ or $$ delimiters. Write exponents as x^2 (caret notation)
or, better, as actual Unicode superscript characters (x²) — never $x^2$.
Write fractions as "a/b" or "(a)/(b)", never \frac{{a}}{{b}}. Use ×, ÷, √,
π directly rather than \times, \div, \sqrt, \pi.

══════════════════════════════════════════════════════════════════════════════
4. QUESTION GENERATION — exact counts, formats, and cognitive levels
══════════════════════════════════════════════════════════════════════════════
GENERATE EXACTLY:
- {easy_n} EASY questions, format "fill_blank": a genuine computation with exactly 4 numeric/expression options (one correct, three plausible near-miss values — not word-guessing). Cognitive level: Remember or Understand.
- {med_n} MEDIUM questions, format "short_answer": a computation requiring one typed final answer (a number or short expression). Include "expected_answer" (string) and, if numeric, "answer_tolerance" (float, absolute tolerance). Cognitive level: Apply or Analyze.
- {hard_n} HARD questions, format "multi_part": ONE multi-step problem with exactly 4 sub-parts (ids "a","b","c","d") that build on each other as genuine PREREQUISITE STEPS — part b) must require the result of part a) to solve, part c) must require part b), etc. (e.g. successive iterations, or sequential steps of one derivation). Each sub-part asks for ONE final value/expression (a small textbox, never a full written proof/essay). Each sub-part needs "expected_answer" and optional "answer_tolerance". Cognitive level: Analyze, Evaluate, or Create.

Every question object needs a "cognitive_level" field — one of: "Remember",
"Understand", "Apply", "Analyze", "Evaluate", "Create" (Bloom's taxonomy) —
matching the actual mental operation the question demands, not just its format.

══════════════════════════════════════════════════════════════════════════════
5. RULES
══════════════════════════════════════════════════════════════════════════════
1. Base every question on the supplied CHUNKS — do not invent content outside them. Reuse the formulas, worked examples, and numeric values already present in the text; construct new-but-analogous computations where the chunk supports it.
2. COVERAGE: draw from every chunk provided at least once before repeating any chunk, unless there are more questions than chunks. Chunks appear in priority order (most-needed first) — earlier chunks in the list should get first priority for a question.
3. Each question needs: "hint" (a single vague level-1 style nudge pointing at the relevant formula/method — deeper hints are generated separately later, so keep this one short and non-revealing), "topic_tags" (1-3 labels), "difficulty_score" (1-5), "difficulty_level".
4. "xai_explanation": a full correct-answer walkthrough (150-220 words) showing the actual working/steps — this is the model solution shown if the student gets it wrong. For multi_part, cover all 4 sub-parts' working.
5. "selection_rationale" (NEW, required, 1 sentence): explain in plain language why THIS question was chosen for THIS student right now — tie it explicitly to the profile above (e.g. "Targets your recurring mistake with factoring" or "Maintenance check on a topic you've already mastered" or "This chunk hasn't been tested yet"). This is shown to the student as part of the session's explainability, so it must reference the real reason, not a generic filler sentence.
6. Every question must include a distinct "id" like "q1","q2",... continuing sequentially across ALL {total_q} questions.

══════════════════════════════════════════════════════════════════════════════
OUTPUT — valid JSON only, no markdown, no commentary before or after the JSON
══════════════════════════════════════════════════════════════════════════════
{{"questions":[
  {{"id":"q1","chunk_index":0,"question_type":"easy","format":"fill_blank","topic":"Topic","topic_tags":["t1"],"difficulty_score":{nd},"difficulty_level":"{nl}","cognitive_level":"Understand","selection_rationale":"...","question_text":"Using the bisection method on f(x)=x^3+4x^2-10 with a=1, b=2, what is the midpoint p1?","blank_word":"1.5","options":["1.5","1.25","1.75","2.0"],"correct_index":0,"hint":"...","xai_explanation":"..."}},
  {{"id":"q2","chunk_index":1,"question_type":"medium","format":"short_answer","topic":"Topic","topic_tags":["t1"],"difficulty_score":{nd},"difficulty_level":"{nl}","cognitive_level":"Apply","selection_rationale":"...","question_text":"Evaluate f(1.5) for f(x)=x^3+4x^2-10.","expected_answer":"2.375","answer_tolerance":0.01,"hint":"...","xai_explanation":"..."}},
  {{"id":"q3","chunk_index":2,"question_type":"hard","format":"multi_part","topic":"Topic","topic_tags":["t1"],"difficulty_score":{nd},"difficulty_level":"{nl}","cognitive_level":"Analyze","selection_rationale":"...","question_text":"Perform 4 iterations of Newton-Raphson on f(x)=x^3-2x-5 starting at x0=2.","sub_parts":[{{"id":"a","prompt":"Part a) Find x1.","expected_answer":"2.1","answer_tolerance":0.01}},{{"id":"b","prompt":"Part b) Using x1, find x2.","expected_answer":"2.09457"}},{{"id":"c","prompt":"Part c) Using x2, find x3.","expected_answer":"2.09455"}},{{"id":"d","prompt":"Part d) Using x3, find x4.","expected_answer":"2.09455"}}],"hint":"...","xai_explanation":"..."}}
]}}"""

def build_question_user_prompt(chunks):
    txt="\n\n".join(f"[CHUNK {c['index']} | Model1:{c['difficulty']['score']}/5 ({c['difficulty']['level']})|conf:{c['difficulty']['confidence']}]\n{c['text']}" for c in chunks)
    return f"CHUNKS (higher Model1 difficulty chunks appear more often on purpose — draw more questions from them):\n\n{txt}\n\nReturn ONLY the JSON object with the exact question counts, formats, and cognitive-level/selection-rationale fields requested."

def build_hint_prompt(q,level,current_answer):
    fmt=q.get("format","fill_blank")
    stage="The student has NOT started answering yet." if not (current_answer or "").strip() \
        else f"The student is mid-answer. What they've typed so far: \"{(current_answer or '')[:300]}\""
    qtext=q.get("question_text","")
    return f"""You are a patient maths tutor giving a PROGRESSIVE hint.
This is hint level {level} of {MAX_HINT_LEVEL} (1 = vague nudge, {MAX_HINT_LEVEL} = walk through the full method — but NEVER state the final answer value/expression outright, even at level {MAX_HINT_LEVEL}).

QUESTION ({fmt}): {qtext}
{"SUB-PARTS: "+json.dumps(q.get("sub_parts",[]),default=str) if fmt=="multi_part" else ""}
STUDENT STATE: {stage}

Guidance by level:
- 1-3: point to the relevant concept or formula only — do not set up the problem.
- 4-6: help set up the first step, referencing their partial work if they have any.
- 7-9: walk through the approach up to (not including) the final computation.
- {MAX_HINT_LEVEL}: show the full method/setup so only plugging in numbers remains.

Write 2-4 SHORT sentences (under 60 words total). Finish your last sentence
completely — a hint that trails off unfinished is worse than a shorter
complete one. This app renders plain text, not LaTeX — never use $ or $$
delimiters; write exponents as x^2 or x² and fractions as a/b, never
\\frac{{a}}{{b}}. Return ONLY the hint text — no JSON, no preamble, no markdown."""

def build_xai_prompt_v2(q,answer_summary,is_correct,time_taken,time_allotted,hints_used):
    fmt=q.get("format","fill_blank")
    return f"""You are an XAI tutor for Nuromathix.

QUESTION FORMAT: {fmt}
QUESTION: {q.get('question_text','')}
{"SUB-PARTS: "+json.dumps(q.get('sub_parts',[]),default=str) if fmt=="multi_part" else ""}
STUDENT ANSWER: {json.dumps(answer_summary,default=str)}
RESULT: {'CORRECT' if is_correct else 'INCORRECT / PARTIALLY INCORRECT'}
TIME: {time_taken:.0f}s of {time_allotted:.0f}s allotted
HINTS USED: {len(hints_used)} (levels: {[h.get('level') for h in hints_used]})

Write feedback (200-260 words):
1. {'Confirm why the answer is correct and deepen the concept.' if is_correct else 'Explain the FULL correct step-by-step solution, numbered steps, showing all working — this is the model solution the student should learn from.'}
2. If incorrect, name the likely mistake pattern (e.g. sign error, wrong formula, arithmetic slip).
3. One memory trick or conceptual anchor.
4. One brief comment on their time usage and hint usage.
5. A short encouraging close.

FORMATTING: plain text only, not LaTeX — never use $ or $$ delimiters;
write exponents as x^2 or x² and fractions as a/b, never \frac{{a}}{{b}}.

Return ONLY: {{"xai_text":"...","confidence_boost":0.1-1.0,"review_topics":["t1"]}}"""

def call_gemini(sys_p,usr_p,max_tokens=8192):
    global GEMINI_WORKS,_GEMINI_COOLDOWN_UNTIL
    import time as _time,socket
    if _time.time()<_GEMINI_COOLDOWN_UNTIL:
        # Still within a rate-limit cooldown — fail fast instead of making
        # a network round-trip that's guaranteed to 429 again, and instead
        # of silently retrying on every hint press until the window passes.
        raise RuntimeError(f"gemini_cooldown: rate-limited, retrying after {int(_GEMINI_COOLDOWN_UNTIL-_time.time())}s")
    # temperature/top_p/top_k are deprecated as of Gemini 3.6 — the API silently
    # ignores them today but Google has stated future model generations will
    # hard-error on them, so they're intentionally omitted here.
    payload=json.dumps({"system_instruction":{"parts":[{"text":sys_p}]},"contents":[{"parts":[{"text":usr_p}]}],"generationConfig":{"maxOutputTokens":max_tokens}}).encode()
    req=urllib.request.Request(GEMINI_URL,data=payload,headers={"Content-Type":"application/json"},method="POST")
    # A fixed 90s timeout was too short once max_tokens got bumped to 16000
    # for the richer batched prompts (cognitive_level + selection_rationale
    # + full XAI for up to 15 questions in one call) — real testing showed
    # Gemini was genuinely generating good content, just taking longer than
    # 90s to finish it, so the connection got killed mid-response and every
    # such call failed with "the read operation timed out" or a truncated-
    # JSON parse error. Scales with the requested output size instead.
    net_timeout=min(240,max(90,max_tokens//60))
    try:
        with urllib.request.urlopen(req,timeout=net_timeout) as r:
            data=json.loads(r.read())
        GEMINI_WORKS=True
        return data["candidates"][0]["content"]["parts"][0]["text"]
    except (socket.timeout,TimeoutError):
        raise RuntimeError(f"gemini_timeout: no response within {net_timeout}s (max_tokens={max_tokens})")
    except urllib.error.HTTPError as e:
        body=e.read().decode()
        if e.code==403:GEMINI_WORKS=False;raise RuntimeError(f"gemini_403: {body[:400]}")
        if e.code==429:
            # Free-tier quota hit — this is TEMPORARY (unlike 403), so don't
            # disable Gemini forever; just back off for a bit so the next
            # several requests (hints, XAI) don't all repeat the same
            # guaranteed-to-fail call while the quota window is still open.
            _GEMINI_COOLDOWN_UNTIL=_time.time()+60
            raise RuntimeError(f"gemini_429: {body[:400]}")
        raise RuntimeError(f"Gemini {e.code}: {body[:400]}")
    except (KeyError,IndexError) as e:
        # candidates missing entirely — usually a safety-filter block with no
        # content returned at all; surface the raw payload so it's diagnosable
        raise RuntimeError(f"Gemini returned no usable content: {e} — raw={json.dumps(data)[:400] if 'data' in dir() else 'n/a'}")

def _extract_json_object(raw):
    """Pulls out the {...} JSON object even if Gemini wrapped it in markdown
    fences or added stray commentary before/after — takes the span from the
    first '{' to its matching closing '}', tracking string/escape state so
    braces inside string values don't confuse the match."""
    start = raw.find("{")
    if start == -1:
        return raw
    depth = 0
    in_str = False
    esc = False
    for i in range(start, len(raw)):
        ch = raw[i]
        if in_str:
            if esc:
                esc = False
            elif ch == "\\":
                esc = True
            elif ch == '"':
                in_str = False
            continue
        if ch == '"':
            in_str = True
        elif ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                return raw[start:i+1]
    return raw[start:]  # unterminated (likely truncated) — return what we have

def _escape_literal_newlines_in_strings(raw):
    """The single most common reason Gemini's 'valid JSON only' output still
    fails strict json.loads: a literal newline/tab typed inside a string
    value (e.g. a multi-line xai_explanation) instead of the escaped \\n.
    Walks the text tracking whether we're inside a double-quoted string and
    escapes raw control characters ONLY there — everything outside strings
    (the actual JSON structure/whitespace) is left untouched."""
    out = []
    in_str = False
    esc = False
    for ch in raw:
        if in_str:
            if esc:
                out.append(ch); esc = False; continue
            if ch == "\\":
                out.append(ch); esc = True; continue
            if ch == '"':
                out.append(ch); in_str = False; continue
            if ch == "\n":
                out.append("\\n"); continue
            if ch == "\r":
                continue
            if ch == "\t":
                out.append("\\t"); continue
            out.append(ch); continue
        if ch == '"':
            in_str = True
        out.append(ch)
    return "".join(out)

_SUPERSCRIPT_MAP=str.maketrans("0123456789","⁰¹²³⁴⁵⁶⁷⁸⁹")

def _clean_math_notation(text):
    """Gemini is trained on LaTeX-heavy math corpora and will often wrap
    expressions in $...$/$$...$$ delimiters and write exponents as x^2 —
    both correct LaTeX conventions, but this app renders plain text, not
    LaTeX, so a stray '$' just shows up as a literal dollar sign in the UI.
    This is a backend safety net applied to every piece of text a student
    sees (questions, hints, XAI) regardless of whether the prompt's
    formatting instruction was followed — it can't be, since Gemini
    doesn't always obey formatting instructions perfectly."""
    if not text or not isinstance(text,str):return text
    # Strip LaTeX dollar-sign delimiters, keeping the inner content.
    text=re.sub(r"\$\$(.+?)\$\$",r"\1",text)
    text=re.sub(r"\$(.+?)\$",r"\1",text)
    # Common LaTeX commands that sometimes slip through anyway.
    text=text.replace("\\times","×").replace("\\cdot","·")
    text=text.replace("\\pi","π").replace("\\infty","∞").replace("\\pm","±")
    text=re.sub(r"\\frac\{([^{}]+)\}\{([^{}]+)\}",r"(\1)/(\2)",text)
    text=re.sub(r"\\sqrt\{([^{}]+)\}",r"√(\1)",text)
    text=re.sub(r"\\sqrt\[(\d+)\]\{([^{}]+)\}",r"\\2^(1/\1)",text)
    # Simple caret exponents -> Unicode superscript for readability:
    # "2^2" -> "2²", "x^3" -> "x³", "(a+b)^2" -> "(a+b)²". Complex exponents
    # like x^(n+1) are left alone — no clean superscript form for those.
    def _sup(m):
        exp=m.group(2)
        if len(exp)<=3 and exp.isdigit():
            return m.group(1)+exp.translate(_SUPERSCRIPT_MAP)
        return m.group(0)
    text=re.sub(r"(\w|\))\^(\d{1,3})",_sup,text)
    return text

def _clean_question_text_fields(q):
    """Applies _clean_math_notation to every user-visible text field on a
    single question dict, in place."""
    if q.get("question_text"):q["question_text"]=_clean_math_notation(q["question_text"])
    if q.get("hint"):q["hint"]=_clean_math_notation(q["hint"])
    if q.get("xai_explanation"):q["xai_explanation"]=_clean_math_notation(q["xai_explanation"])
    if q.get("selection_rationale"):q["selection_rationale"]=_clean_math_notation(q["selection_rationale"])
    for sp in q.get("sub_parts",[]) or []:
        if sp.get("prompt"):sp["prompt"]=_clean_math_notation(sp["prompt"])
    return q

def parse_json_response(raw):
    raw = raw.strip()
    if "```" in raw:
        raw = raw.split("```", 1)[1]
        if raw.lstrip().startswith("json"):
            raw = raw.lstrip()[4:]
    raw = _extract_json_object(raw.strip())
    try:
        return json.loads(raw)
    except json.JSONDecodeError as e:
        log.warning("[json] strict parse failed (%s) — retrying with literal-newline repair", e)
        repaired = _escape_literal_newlines_in_strings(raw)
        try:
            return json.loads(repaired)
        except json.JSONDecodeError as e2:
            log.error("[json] repair also failed: %s — raw sample: %s", e2, raw[:500])
            raise

# ══════════════════════════════════════════════════════════════════════════════
# Offline fallback generator (used if Gemini unavailable/403)
# ══════════════════════════════════════════════════════════════════════════════
DISTRACTOR_POOL=[
    ["acceleration","velocity","momentum","displacement"],
    ["mitosis","meiosis","osmosis","diffusion"],
    ["oxidation","reduction","hydrolysis","neutralisation"],
    ["differentiation","integration","derivation","substitution"],
    ["convection","conduction","radiation","absorption"],
    ["frequency","amplitude","wavelength","period"],
    ["photosynthesis","respiration","transpiration","fermentation"],
    ["hypothesis","theory","law","postulate"],
    ["stoichiometry","enthalpy","entropy","equilibrium"],
    ["polynomial","monomial","binomial","trinomial"],
]

def _key_sentences(text,n=8):
    sents=re.split(r'(?<=[.!?])\s+',text)
    sents=[s.strip() for s in sents if len(s.split())>=7]
    def score(s):
        return sum(1 for kw in ['is','are','refers','defined','called','means','represents'] if kw in s.lower())
    return sorted(sents,key=score,reverse=True)[:n]

def _make_blank(sent):
    stop={'the','a','an','is','are','was','were','be','been','have','has','had','do','does','will','would','could','should','may','might','must','can','to','of','in','on','at','by','for','with','about','into','from','and','or','but','if','as','it','its','this','that','these','those','which','who','what','when','where','how','their','they','we','its','our','your'}
    words=sent.split()
    cands=[(i,w) for i,w in enumerate(words) if len(w)>5 and w.lower().rstrip(".,;:") not in stop and w[0].isalpha() and i>1]
    if not cands:return None
    ci,cw=random.choice(cands[-max(1,len(cands)//2):])
    clean=cw.rstrip('.,;:')
    blanked=" ".join("_____" if i==ci else w for i,w in enumerate(words)).strip()
    # The source sentence often already ends in ./?/!/a closing quote (real
    # textbook prose, or a practice question that was already phrased as a
    # question) — blindly appending "?" produced visible artifacts like
    # "...is the sum of 127 and 59 ??" (doubled) or "...and b\".?" (a
    # trailing quote immediately followed by a stray period-question mark).
    if blanked and blanked[-1] not in '.?!"\'':
        blanked+="?"
    return blanked,clean

# Real, generic distractor words for prose fill-blank questions when the
# correct word isn't in DISTRACTOR_POOL. This used to fabricate fake words
# by truncating the correct answer and appending a random suffix (e.g.
# "difference" -> "differetion"/"differeness"/"differeence") — grammatically
# broken pseudo-words presented as real multiple-choice options. Every
# candidate here is either a real word pulled from elsewhere in the same
# passage, or a real word from a small generic maths-vocabulary bank.
_GENERIC_DISTRACTOR_BANK=["sum","product","quotient","ratio","factor","multiple",
    "remainder","coefficient","variable","constant","expression","equation",
    "function","interval","sequence","gradient","tangent","integer","fraction",
    "decimal","percentage","average","outcome","denominator","numerator"]

def _distractors(correct,level,chunk_text=None):
    for grp in DISTRACTOR_POOL:
        if correct.lower() in [g.lower() for g in grp]:
            return [g for g in grp if g.lower()!=correct.lower()][:3]
    d=[]
    seen={correct.lower()}
    if chunk_text:
        candidates=[w for w in re.findall(r"[A-Za-z]{6,}",chunk_text) if w.lower() not in seen]
        random.shuffle(candidates)
        for w in candidates:
            wl=w.lower()
            if wl in seen:continue
            seen.add(wl);d.append(w)
            if len(d)==3:break
    if len(d)<3:
        pool=[w for w in _GENERIC_DISTRACTOR_BANK if w.lower() not in seen]
        random.shuffle(pool)
        for w in pool:
            if len(d)==3:break
            d.append(w);seen.add(w.lower())
    return d[:3]

def _fallback_qa_pair(chunk):
    """Returns (prompt_text, answer) drawn from one chunk, used by every
    fallback format. Falls back to a naive final-word pick if no good
    sentence is found. LAST-RESORT ONLY — see _fallback_computation_pair,
    which is tried first and produces genuine computation questions."""
    sents=_key_sentences(chunk["text"])
    for s in sents:
        if _is_frontmatter_like(s):continue  # skip promo/nav sentences even
        # inside an otherwise-fine chunk (see _is_frontmatter_like's docstring
        # — a 300-word chunk can average out as "mostly math" while still
        # containing one course-catalog/website blurb sentence like this)
        r=_make_blank(s)
        if r:return r
    # Every sentence was either junk or unusable — this chunk is effectively
    # dead for question purposes. The old naive fallback below used to grab
    # the first 25 raw words with NO filtering at all, which is exactly how
    # promotional text still leaked through even with the per-sentence check
    # above (a chunk that's ENTIRELY junk sentences hits this line for every
    # single one of them). Check it too before ever quoting it verbatim.
    window=" ".join(chunk["text"].split()[:60])
    if _is_frontmatter_like(window):
        topic=_topic_of(chunk)
        return f"This section on {topic.lower()} does not contain enough gradeable content — please review the material directly.","N/A"
    words=chunk["text"].split()[:25]
    ans=next((w for w in reversed(words) if len(w)>5),"concept")
    return " ".join("_____" if w==ans else w for w in words)+"?",ans

# ── Numeric-fact extraction (real computation, not word-guessing) ─────────────
# Maths textbooks are full of worked examples: "p1 = 1.5", "f(1.25) = -1.797",
# "x2 = 2.09457". These are genuine, verifiable computed values straight from
# the source material — asking a student "what is p2 in this worked example?"
# tests actual maths recall/computation, unlike blanking a random prose word.
# LIMITATION: PDF text extraction flattens superscripts (x³ becomes "x3" with
# no marker), so this occasionally mis-parses an exponent as part of a decimal
# value. This is a PDF-extraction limitation, not fixable by regex alone — an
# LLM (Gemini) reads that ambiguity from context far more reliably, which is
# why Gemini remains the recommended primary path; this fallback is the
# best-effort offline substitute when no API key is set.
_NUMERIC_FACT_RE=re.compile(r'\b([fpxngh][a-zA-Z0-9_]{0,3}(?:\([^)]{1,15}\))?)\s*=\s*(-?\d+\.\d+|-?\d+)')
_BLACKLISTED_LABELS={"n","i","j","k","e"}   # loop indices / Euler's-number ambiguity — not meaningful quiz facts

def _extract_numeric_facts(text):
    facts=[]
    for sent in re.split(r'(?<=[.!?])\s+',text):
        if len(sent.split())<4:continue
        for m in _NUMERIC_FACT_RE.finditer(sent):
            label,value=m.group(1),m.group(2)
            if label.lower() in _BLACKLISTED_LABELS:continue
            trailing=sent[m.end():m.end()+2].strip()
            # Reject if the captured number is immediately followed by an
            # operator/paren — that means it's a mid-expression fragment, not
            # a resolved final value. This is what catches PDF superscript-
            # flattening artifacts like "f(1.5) = 1.53 + 4(1.5)2 -10 = 2.375",
            # where "1.53" is really "1.5³" glued together mid-formula and
            # the TRUE result (2.375) is further along — safer to skip the
            # whole fact than risk quizzing on the wrong value.
            if trailing[:1] in "+-*/^(":
                continue
            facts.append({"label":label,"value":value,"context":sent.strip()})
    return facts

def _numeric_distractors(value_str):
    try:
        v=float(value_str)
    except ValueError:
        return [value_str+"1",value_str+"2",value_str+"3"]
    deltas=[0.1,-0.1,0.25,-0.25,0.5,-0.5,1.0,-1.0]
    random.shuffle(deltas)
    seen={value_str};out=[]
    for d in deltas:
        cand=round(v+d*max(abs(v),1),4)
        s=str(cand)
        if s not in seen:
            seen.add(s);out.append(s)
        if len(out)==3:break
    while len(out)<3:
        out.append(str(round(v+random.uniform(-2,2),4)))
    return out

def _fallback_computation_pair(chunk):
    """Preferred fallback question source: a real computed value from a
    worked example in this chunk, with the sentence it came from as context.
    Falls back to _fallback_qa_pair (word-blank) only if the chunk has no
    extractable numeric facts (e.g. a purely definitional/theorem chunk)."""
    facts=_extract_numeric_facts(chunk["text"])
    if not facts:
        return (*_fallback_qa_pair(chunk),False)
    fact=random.choice(facts)
    marker=f"{fact['label']} = {fact['value']}"
    if marker in fact["context"]:
        stem=fact["context"].replace(marker,f"{fact['label']} = _____",1)
    else:
        stem=fact["context"]+f" What is the value of {fact['label']}?"
    return stem,fact["value"],True

def _next_difficulty(profile):
    """Shared by build_model2_system_prompt, generate_questions_fallback, and
    the grounding-repair pass, so a repaired question lands at the same
    target difficulty the rest of the session was generated at."""
    avg=profile.get("avg_difficulty_score",3);mr=profile.get("mistake_rate",0.5);hr=profile.get("hint_press_rate",0.0)
    if mr>0.60 or hr>0.70:nd=max(1,avg-1)
    elif mr<0.20 and hr<0.20:nd=min(5,avg+1)
    else:nd=avg
    return nd,DLVL.get(nd,"medium")

_TOPIC_STOPWORDS={"additional","chapter","section","note","notes","example","examples",
    "theorem","remark","remarks","introduction","preface","appendix","summary","exercise",
    "exercises","solution","solutions","answer","answers","since","because","however",
    "therefore","this","that","these","those","when","where","what","which","video",
    "lecture","lectures","copyright","published","edition","author","chegg","omegalearn"}

def _topic_of(chunk):
    words=[w.strip(".,;:()[]") for w in chunk["text"].split()[:80]]
    def is_word_like(w):
        return w.replace("-","").replace("'","").isalpha()
    candidates=[w for w in words if len(w)>5 and w[0].isupper() and is_word_like(w)
        and w.lower() not in _TOPIC_STOPWORDS]
    if not candidates:
        return "Practice Question"
    # Prefer a word that recurs (more likely a real topic noun than a
    # one-off capitalised word at a sentence start) over the first hit.
    from collections import Counter
    counts=Counter(w.lower() for w in candidates)
    best=max(candidates,key=lambda w:(counts[w.lower()],-words.index(w) if w in words else 0))
    return best

def _build_fill_blank_question(chunk,nd,nl,qid):
    """Builds one EASY fill_blank question grounded in `chunk`. Extracted
    so both the offline generator AND the grounding-repair pass (see
    _grounding_ok / verify_and_repair_grounding) can produce a single
    replacement question tied to one specific chunk, instead of duplicating
    this logic in two places."""
    qtxt,answer,is_computed=_fallback_computation_pair(chunk)
    dists=_numeric_distractors(answer) if is_computed else _distractors(answer,nl,chunk["text"])
    opts=[answer]+dists;random.shuffle(opts);cidx=opts.index(answer)
    topic=_topic_of(chunk)
    if is_computed:
        xai=(f"The correct value is {answer}, computed directly from the worked example in this section. "
             f"The other options are plausible nearby values but don't match the actual computation shown. "
             f"Re-work the calculation step shown in the passage to confirm {answer}. Keep practicing — accuracy comes with repetition!")
    else:
        xai=(f"The correct answer is '{answer}'. It fits because the passage specifically describes this concept. "
             f"'{dists[0] if dists else 'Option B'}' is incorrect — related but different. "
             f"'{dists[1] if len(dists)>1 else 'Option C'}' is incorrect — different mechanism/property. "
             f"'{dists[2] if len(dists)>2 else 'Option D'}' is incorrect — different category. "
             f"Memory trick: link '{answer}' to the context of this passage. Keep going!")
    return {"id":qid,"chunk_index":chunk["index"],"question_type":"easy","format":"fill_blank",
        "topic":topic,"topic_tags":[topic.lower(),nl],"difficulty_score":nd,"difficulty_level":nl,
        "time_allotted_seconds":TIME_ALLOTMENT["easy"],"question_text":qtxt,"blank_word":answer,
        "options":opts,"correct_index":cidx,"hint":f"Work through the computation shown for {topic.lower()} step by step.","xai_explanation":xai}

def _build_short_answer_question(chunk,nd,nl,qid):
    """MEDIUM short_answer counterpart to _build_fill_blank_question — see
    that docstring for why this is a standalone, chunk-scoped builder."""
    qtxt,answer,is_computed=_fallback_computation_pair(chunk)
    topic=_topic_of(chunk)
    is_numeric=is_computed or answer.replace('.','',1).replace('-','',1).isdigit()
    if is_computed:
        xai=(f"The correct value is {answer}. Trace through the computation shown in the passage step by step to "
             f"confirm this result. If your answer differs, check for a sign error or an arithmetic slip in an "
             f"intermediate step — that's the most common cause of a mismatch here.")
        question_text=qtxt
    else:
        xai=(f"The correct answer is '{answer}'. This passage directly names it in that context. "
             f"Re-read the sentence around the blank for the exact wording used. Memory trick: tie '{answer}' to {topic.lower()}.")
        question_text="Fill in the missing term: "+qtxt
    return {"id":qid,"chunk_index":chunk["index"],"question_type":"medium","format":"short_answer",
        "topic":topic,"topic_tags":[topic.lower(),nl],"difficulty_score":nd,"difficulty_level":nl,
        "time_allotted_seconds":TIME_ALLOTMENT["medium"],"question_text":question_text,
        "expected_answer":answer,"answer_tolerance":0.01 if is_numeric else None,
        "hint":f"Work through the {topic.lower()} computation shown, one step at a time.","xai_explanation":xai}

# ── Relevance / grounding check ────────────────────────────────────────────
# Gemini is instructed to base every question strictly on the supplied
# chunks (see build_model2_system_prompt rule #1), but LLMs occasionally
# drift toward generic textbook knowledge instead of the actual uploaded
# passage. This is a cheap, deterministic safety net run AFTER generation:
# it checks whether the question's own wording actually shares vocabulary
# with the chunk it claims to come from. It cannot verify mathematical
# correctness, only topical grounding in the uploaded material.
_GROUND_STOPWORDS={"this","that","these","those","what","which","find","value","using",
    "given","with","and","for","from","into","upon","your","the","a","an","is","are",
    "was","were","will","would","could","should","about","first","then","following"}
_GROUND_MIN_OVERLAP=0.15

def _ground_tokens(s):
    return {w for w in re.findall(r"[a-zA-Z]{4,}",(s or "").lower()) if w not in _GROUND_STOPWORDS}

def _grounding_ok(question_text,chunk_text,extra_terms=None):
    qt=_ground_tokens(question_text)
    if extra_terms:qt|=_ground_tokens(" ".join(str(t) for t in extra_terms))
    if not qt:return True   # nothing meaningful to check (pure numeric/symbolic question)
    ct=_ground_tokens(chunk_text)
    if not ct:return True
    overlap=len(qt & ct)/len(qt)
    return overlap>=_GROUND_MIN_OVERLAP

def verify_and_repair_grounding(questions,chunks,nd,nl,used_gemini):
    """Runs after question generation (Gemini or fallback) and:
    1. Stamps every question with the Model 1 difficulty data of the chunk
       it's tied to, so the frontend can show/verify Model 1's actual output
       per question (score, level, confidence, source: model1_rf vs heuristic).
    2. Checks each question is actually grounded in its claimed source chunk,
       and FLAGS (only) any that fail. This used to silently swap flagged
       Gemini questions for the crude offline generator's output — but for
       formula-dense chunks (theorems, symbolic notation) the word-overlap
       heuristic below produces false positives, and the "repair" was worse
       than the question it replaced: a coherent, mostly-fine Gemini question
       became a garbled fallback one with scrambled-letter distractors. A
       flagged-but-imperfect Gemini question is still better than that, so
       this now only logs/flags for visibility and never rewrites content."""
    chunk_by_idx={c["index"]:c for c in chunks}
    flagged=0
    for q in questions:
        c=chunk_by_idx.get(q.get("chunk_index"))
        if not c:continue
        d=c["difficulty"]
        q["model1_difficulty_score"]=d["score"];q["model1_difficulty_level"]=d["level"]
        q["model1_confidence"]=d["confidence"];q["model1_source"]=d["source"]

        fmt=q.get("format","fill_blank")
        extra=q.get("options",[]) if fmt=="fill_blank" else \
              [q.get("expected_answer","")] if fmt=="short_answer" else \
              [sp.get("prompt","") for sp in q.get("sub_parts",[])]
        grounded=_grounding_ok(q.get("question_text",""),c["text"],extra)
        q["grounded"]=grounded
        if not grounded:flagged+=1
    if flagged:
        log.warning("[grounding] %d/%d questions flagged as low-overlap with their source chunk "
            "(not replaced — flag is informational only)",flagged,len(questions))
    return {"checked":len(questions),"flagged":flagged,"repaired":0}
    return {"checked":len(questions),"flagged":flagged,"repaired":regenerated}

def generate_questions_fallback(ordered_chunks,profile,easy_n,med_n,hard_n):
    nd,nl=_next_difficulty(profile)
    pool=ordered_chunks or []
    if not pool:return []
    qi=[0]
    def next_chunk():
        return pool[qi[0]%len(pool)] if pool else pool[0]

    questions=[]
    # EASY — fill_blank, but MCQ options are now numeric distractors when the
    # source is a real computed value, not vocabulary-style word swaps
    for _ in range(easy_n):
        c=next_chunk();qi[0]+=1
        questions.append(_build_fill_blank_question(c,nd,nl,f"q{len(questions)+1}"))
    # MEDIUM — short_answer, typed final value/term
    for _ in range(med_n):
        c=next_chunk();qi[0]+=1
        questions.append(_build_short_answer_question(c,nd,nl,f"q{len(questions)+1}"))
    # HARD — multi_part: prefer 4 facts from the SAME chunk sharing a label
    # prefix (e.g. p1,p2,p3,p4 from one iteration table) so the sub-parts
    # form a coherent sequence rather than 4 unrelated facts
    for _ in range(hard_n):
        c=next_chunk();qi[0]+=1
        facts=_extract_numeric_facts(c["text"])
        by_prefix={}
        for f in facts:
            prefix=re.match(r'[a-zA-Z]+',f["label"])
            key=prefix.group(0) if prefix else f["label"]
            by_prefix.setdefault(key,[]).append(f)
        sequence=max(by_prefix.values(),key=len) if by_prefix else []
        sub_parts=[]
        if len(sequence)>=4:
            chosen=sequence[:4]
            for label,f in zip(["a","b","c","d"],chosen):
                sub_parts.append({"id":label,"prompt":f"Part {label}) In this worked example, what is {f['label']}?",
                    "expected_answer":f["value"],"answer_tolerance":0.01})
            topic=_topic_of(c)
        else:
            # not enough facts in one chunk for a coherent sequence — draw
            # one fact/blank per sub-part from up to 4 chunks instead
            for label in ["a","b","c","d"]:
                cc=next_chunk();qi[0]+=1
                qtxt,answer,is_computed=_fallback_computation_pair(cc)
                is_numeric=is_computed or answer.replace('.','',1).replace('-','',1).isdigit()
                prompt=f"Part {label}) {qtxt}" if is_computed else f"Part {label}) Fill in the missing term: {qtxt}"
                sub_parts.append({"id":label,"prompt":prompt,"expected_answer":answer,
                    "answer_tolerance":0.01 if is_numeric else None})
            topic=_topic_of(c)
        xai=("Full solution:\n"+"\n".join(f"Part {sp['id']}) → {sp['expected_answer']}" for sp in sub_parts)+
             "\nWork through each part in order and check your intermediate values against these before moving to the next part.")
        questions.append({"id":f"q{len(questions)+1}","chunk_index":c["index"],"question_type":"hard","format":"multi_part",
            "topic":topic,"topic_tags":[topic.lower(),nl],"difficulty_score":min(5,nd+1),"difficulty_level":DLVL.get(min(5,nd+1),nl),
            "time_allotted_seconds":TIME_ALLOTMENT["hard"],"question_text":f"Multi-part problem on {topic}. Answer each part below.",
            "sub_parts":sub_parts,"hint":"Work through each part in order — later parts often build on earlier ones.","xai_explanation":xai})
    return questions

def generate_fallback_hint(q,level,current_answer):
    """Used ONLY when Gemini itself errors out for this specific request
    (Gemini being reachable is now the normal path — see call_gemini/GEMINI_URL).
    Previously this returned the exact same sentence for levels 1-3, another
    identical sentence for 4-6, etc. — genuinely unhelpful and repetitive.
    Now every level says something distinct, referencing the real topic and
    the student's own partial answer where possible."""
    topic=q.get("topic","this section")
    fmt=q.get("format","fill_blank")
    started=bool((current_answer or "").strip())
    qtext=q.get("question_text","")
    snippet=(qtext[:90]+"…") if len(qtext)>90 else qtext

    if level==1:
        return f"Start by re-reading the question carefully: \"{snippet}\" — what concept from {topic} is it testing?"
    if level==2:
        return f"Think about which formula or rule from {topic} applies here before you try to compute anything."
    if level==3:
        return ("You've started — check that your first step correctly sets up the problem before going further."
                 if started else
                 f"Identify what's actually being asked: is this asking for a value, a term, or a step in a method?")
    if level==4:
        return f"Write down what you already know from the passage about {topic}, then decide what's still missing."
    if level==5:
        return ("Look back at what you've typed so far — does it match the structure of a worked example from this passage?"
                 if started else
                 f"Try restating the question in your own words — that usually reveals the first step for {topic}.")
    if level==6:
        return f"Focus specifically on {topic}: re-read the exact sentence in the passage this question is built from."
    if level==7:
        if fmt=="multi_part":
            return "Work through each part in order — later parts usually reuse the result from the part before it."
        return f"Set up the calculation step by step for {topic}, but don't compute the final number yet."
    if level==8:
        return f"You're most of the way there — walk through the {topic} method one more time, checking each step against the passage."
    if level==9:
        return f"Double-check for a sign error or a swapped value — that's the most common slip on {topic} problems like this."
    return f"You're very close — the answer is the exact term/value this passage gives for {topic}. One more careful pass should confirm it."

def generate_xai_fallback(q,is_correct,answer_summary=None):
    """Used ONLY when Gemini itself errors out for this specific request.
    Previously this ignored the student's actual answer entirely and returned
    the exact same canned paragraph to everyone regardless of what they typed
    or selected — it didn't even change wording between two different wrong
    answers. This version at least reflects what the student actually did."""
    fmt=q.get("format","fill_blank")
    topic=q.get("topic","this concept")
    base=q.get("xai_explanation","Review this concept carefully.")

    given_txt=None
    if answer_summary:
        if fmt=="fill_blank":given_txt=answer_summary.get("selected_text")
        elif fmt=="short_answer":given_txt=answer_summary.get("answer_text")

    if is_correct:
        text=f"Correct! {base}"
    elif given_txt:
        text=(f"You answered '{given_txt}', which isn't quite right for this {topic} question. {base} "
              f"Compare your answer against the correct one above and re-trace where your working diverged.")
    else:
        text=base
    return{"xai_text":text,"confidence_boost":0.75 if is_correct else 0.35,"review_topics":q.get("topic_tags",[])}

# ══════════════════════════════════════════════════════════════════════════════
# Grading helpers
# ══════════════════════════════════════════════════════════════════════════════
def _answers_match(given,expected,tolerance=None):
    if given is None:return False
    g=str(given).strip()
    if not g:return False
    e=str(expected).strip()
    try:
        gf=float(g.replace(",",""));ef=float(e.replace(",",""))
        tol=tolerance if tolerance is not None else max(abs(ef)*0.02,0.01)
        return abs(gf-ef)<=tol
    except ValueError:
        pass
    norm=lambda s:re.sub(r"[^a-z0-9]","",s.lower())
    return norm(g)==norm(e)

def grade_answer(q,ua):
    fmt=q.get("format","fill_blank")
    if fmt=="fill_blank":
        si=ua.get("selected_index",-1)
        ic=si==q.get("correct_index")
        opts=q.get("options",[])
        summary={"selected_index":si,"selected_text":opts[si] if 0<=si<len(opts) else None}
        return ic,summary,1.0 if ic else 0.0
    if fmt=="short_answer":
        given=ua.get("answer_text","")
        ic=_answers_match(given,q.get("expected_answer",""),q.get("answer_tolerance"))
        return ic,{"answer_text":given},1.0 if ic else 0.0
    # multi_part
    subs=ua.get("sub_answers",{}) or {}
    correct_flags={}
    for sp in q.get("sub_parts",[]):
        given=subs.get(sp["id"],"")
        correct_flags[sp["id"]]=_answers_match(given,sp.get("expected_answer",""),sp.get("tolerance"))
    n=max(len(q.get("sub_parts",[])),1)
    partial=sum(correct_flags.values())/n
    ic=partial==1.0
    return ic,{"sub_answers":subs,"sub_correct":correct_flags,"partial_score":round(partial,3)},partial

# ══════════════════════════════════════════════════════════════════════════════
# Learner profile + forgetting curve (Model 2 output → scheduling input)
# ══════════════════════════════════════════════════════════════════════════════
def derive_learner_profile(session):
    answers=session.get("answers",[]);chunks=session.get("chunks",[])
    scores=[c["difficulty"]["score"] for c in chunks]
    avg_diff=round(sum(scores)/len(scores)) if scores else 3
    base={"avg_difficulty_score":avg_diff,"session_count":session.get("session_count",1),"has_history":bool(answers)}
    if not answers:
        base.update({"hint_press_rate":0.0,"mistake_rate":0.0,"avg_time_seconds":35.0,
            "mistake_patterns":[],"preferred_pace":"medium","avg_score":1.0,
            "accuracy_by_type":{},"timeout_rate":0.0,"avg_overtime_seconds":0.0,
            "avg_hint_level":0.0,"hint_usage_rate":0.0})
        return base

    total=len(answers);correct_scores=[a.get("score",1.0 if a.get("is_correct") else 0.0) for a in answers]
    correct=sum(1 for a in answers if a.get("is_correct"))
    hint_events=[h for a in answers for h in a.get("hints_used",[])]
    times=[a.get("time_taken",35.0) for a in answers];avg_t=sum(times)/len(times) if times else 35.0
    pace="medium"
    if avg_t>55:pace="slow"
    elif avg_t<22:pace="fast"
    from collections import Counter
    missed=[]
    for a in answers:
        if not a.get("is_correct",True):missed.extend(a.get("topic_tags",[]))

    type_buckets={}
    for a in answers:
        t=a.get("question_type","easy")
        type_buckets.setdefault(t,[]).append(a.get("score",1.0 if a.get("is_correct") else 0.0))
    accuracy_by_type={k:round(sum(v)/len(v),3) for k,v in type_buckets.items() if v}

    timeouts=sum(1 for a in answers if a.get("timed_out"))
    overtimes=[a.get("overtime_seconds",0) for a in answers if a.get("overtime_seconds",0)>0]
    hint_levels=[h.get("level",1) for h in hint_events]

    base.update({
        "hint_press_rate":round(len(hint_events)/total,3) if total else 0.0,
        "mistake_rate":round(1-(sum(correct_scores)/total),3) if total else 0.0,
        "avg_time_seconds":round(avg_t,1),
        "mistake_patterns":[t for t,_ in Counter(missed).most_common(3)],
        "preferred_pace":pace,
        "avg_score":round(sum(correct_scores)/total,3) if total else 1.0,
        "accuracy_by_type":accuracy_by_type,
        "timeout_rate":round(timeouts/total,3) if total else 0.0,
        "avg_overtime_seconds":round(sum(overtimes)/len(overtimes),1) if overtimes else 0.0,
        "avg_hint_level":round(sum(hint_levels)/len(hint_levels),2) if hint_levels else 0.0,
        "hint_usage_rate":round(sum(1 for a in answers if a.get("hints_used"))/total,3) if total else 0.0,
    })
    return base

def compute_forgetting_curve(p,mode="fixed",study_days=7):
    avg=p.get("avg_score",0.5);mr=p.get("mistake_rate",0.5);hr=p.get("hint_press_rate",0.3);ns=p.get("session_count",1)
    S=1.0+(avg*3.5)-(mr*2.0)-(hr*1.5)+(ns*0.4);S=max(0.5,min(S,6.0))
    thr=0.80;gap=S*(-math.log(thr))

    # ── pace by study mode: never let gaps balloon into months, never crush
    #    "until mastery" into a single week either ──
    if mode=="until_mastery":
        gap=max(MASTERY_MIN_GAP_DAYS,min(gap,MASTERY_MAX_GAP_DAYS))
        session_cap=MASTERY_MAX_SESSIONS
    else:
        gap=max(1,min(gap,FIXED_MODE_MAX_GAP_DAYS,max(1,study_days-ns)))
        session_cap=None

    d1=max(1,round(gap*0.25));d2=max(2,round(gap*0.60));d3=max(4,round(gap));d4=max(7,round(gap*2.0))
    now=datetime.utcnow()
    sched=[{"session":i+1,"days_from_now":d,"date":(now+timedelta(days=d)).strftime("%Y-%m-%d")} for i,d in enumerate([d1,d2,d3,d4])]
    pts=[{"day":t,"retention":round(math.exp(-t/max(S,0.01)),4)} for t in range(0,d4+1)]
    # mastery_reached is computed separately (see compute_mastery) using the
    # full multi-session history, not from this single session's numbers —
    # left False here and overwritten by the caller after curve computation.
    return{"stability":round(S,3),"optimal_gap_days":round(gap,2),"threshold":thr,"next_sessions":sched,
        "next_review_date":sched[0]["date"],"next_review_days":d1,"mastery_reached":False,
        "session_cap":session_cap,"curve_points":pts,"formula":f"R(t) = e^(-t / {round(S,2)})"}

def compute_mastery(material_id,stability,session_cap):
    """Real, multi-session mastery — not 'the latest session scored 90%'.
    That old rule let one lucky session after two mediocre ones flip
    mastery on, which is exactly the shallow definition flagged as wrong.
    Mastery now requires ALL of:
      - at least 3 completed sessions for this material (never mastered on
        a first/second attempt, no matter how well it went)
      - sustained accuracy: both the AVERAGE and the FLOOR (minimum) of the
        last 3 completed sessions must be high — one weak recent session
        blocks mastery even if the average looks fine
      - low hint dependency in those recent sessions — leaning on hints
        to get there isn't independent mastery
      - a durable memory strength (S) from the forgetting curve itself —
        ties mastery to actual predicted retention, not just raw accuracy
    The one exception: hitting the hard session cap in "until mastery" mode
    ends the loop regardless, so a student isn't stuck in an infinite
    review cycle if they've already done the maximum sessions allowed."""
    history=_sessions_for_material(material_id)
    completed=[s for s in history if s.get("status")=="complete" and s.get("score") is not None]
    if session_cap is not None and len(completed)>=session_cap:
        return True
    if len(completed)<3:
        return False
    recent=completed[-3:]
    scores=[s["score"] for s in recent]
    avg_recent=sum(scores)/len(scores)
    min_recent=min(scores)
    hint_rates=[s.get("learner_profile",{}).get("hint_press_rate",0) for s in recent]
    avg_hint_rate=sum(hint_rates)/len(hint_rates) if hint_rates else 0
    sustained_accuracy=avg_recent>=0.85 and min_recent>=0.75
    low_hint_dependency=avg_hint_rate<=0.35
    durable_retention=stability>=4.0
    return sustained_accuracy and low_hint_dependency and durable_retention

def _strip(qs):
    """What the frontend receives before answering: never the correct_index,
    expected_answer/tolerance, xai_explanation, or the base 'hint' (progressive
    hints are fetched one at a time via /session/<sid>/question/<qid>/hint)."""
    hidden_top={"correct_index","expected_answer","answer_tolerance","xai_explanation","hint"}
    out=[]
    for q in qs:
        clean={k:v for k,v in q.items() if k not in hidden_top}
        if q.get("format")=="multi_part":
            clean["sub_parts"]=[{k:v for k,v in sp.items() if k not in("expected_answer","tolerance","answer_tolerance")} for sp in q.get("sub_parts",[])]
        out.append(clean)
    return out

# ══════════════════════════════════════════════════════════════════════════════
# ROUTES
# ══════════════════════════════════════════════════════════════════════════════
@app.route("/health",methods=["GET"])
def health():
    return jsonify({"status":"ok","model1_loaded":MODEL1_RF is not None,
        "gemini_status":"working" if GEMINI_WORKS else "fallback" if GEMINI_WORKS is False else "untested",
        "model1_classes":MODEL1_RF.classes_.tolist() if MODEL1_RF else[],
        "mongo_connected":_sessions_col is not None and _materials_col is not None,
        "shap_available":MODEL1_SHAP_EXPLAINER is not None})

@app.route("/upload",methods=["POST"])
def upload():
    """Uploads and persists a MATERIAL under the user's profile — this only
    ever needs to happen once per document. Starting a quiz session on it
    afterwards (including a 2nd, 3rd, ... session later) is a separate call
    to POST /material/<material_id>/session/start and never requires
    re-uploading. user_id should be the Firebase uid from the frontend;
    falls back to 'anonymous' only for quick manual/curl testing."""
    if "file" not in request.files:return jsonify({"error":"No file"}),400
    user_id=request.form.get("user_id","anonymous")
    filename=request.files["file"].filename or "Untitled.pdf"
    pdf=request.files["file"].read()
    sd=int(request.form.get("study_days",7));mode=request.form.get("mode","fixed")

    ct,full_text=extract_chunks(pdf)
    if not ct:return jsonify({"error":"Cannot extract text from this PDF."}),422

    is_math,math_confidence,math_reason=is_math_document(full_text)
    if not is_math:
        log.info("[upload] rejected non-math doc: %s",math_reason)
        return jsonify({"error":"This doesn't look like a mathematics document. Nuromathix currently only supports maths study material.",
            "is_math":False,"math_confidence":math_confidence,"debug_reason":math_reason}),422

    chunks=[{"index":i,"text":t,"difficulty":predict_difficulty(t)} for i,t in enumerate(ct)]
    mid=str(uuid.uuid4())
    summary={lvl:sum(1 for c in chunks if c["difficulty"]["level"]==lvl) for lvl in["very_easy","easy","medium","hard","very_hard"]}
    summary["avg_score"]=round(sum(c["difficulty"]["score"] for c in chunks)/len(chunks),2)

    # Real SHAP attribution — only for the hardest few chunks (the ones
    # actually worth explaining "why is this hard"), since TreeExplainer is
    # a genuine per-call cost (~0.1-1s) and running it on all 40 possible
    # chunks would meaningfully slow every upload down.
    SHAP_EXPLAIN_MAX_CHUNKS=6
    hardest=sorted(chunks,key=lambda c:-c["difficulty"]["score"])[:SHAP_EXPLAIN_MAX_CHUNKS]
    word_totals={}
    for c in hardest:
        feats=explain_difficulty(c["text"],c["difficulty"]["score"])
        c["difficulty"]["shap_top_features"]=feats
        for f in feats:
            word_totals[f["word"]]=word_totals.get(f["word"],0.0)+f["contribution"]
    ranked_words=sorted(word_totals.items(),key=lambda kv:-abs(kv[1]))[:8]
    summary["difficulty_explanation"]=[
        {"word":w,"contribution":round(v,4),"direction":"increases" if v>0 else "decreases"}
        for w,v in ranked_words]

    _material_save(mid,{"id":mid,"user_id":user_id,"filename":filename,"uploaded_at":datetime.utcnow().isoformat(),
        "chunks":chunks,"study_days":sd,"mode":mode,"difficulty_summary":summary,
        "chunk_coverage":{str(c["index"]):0 for c in chunks},"session_count":0})
    log.info("[upload] material_id=%s user=%s chunks=%d avg=%.1f is_math=%s conf=%.2f shap_words=%d",
        mid,user_id,len(chunks),summary["avg_score"],is_math,math_confidence,len(summary["difficulty_explanation"]))
    return jsonify({"material_id":mid,"filename":filename,"total_chunks":len(chunks),"difficulty_summary":summary,
        "is_math":True,"math_confidence":math_confidence})

def _sessions_for_user(user_id):
    if _sessions_col is not None:
        return list(_sessions_col.find({"user_id":user_id}).sort("completed_at",1))
    return sorted([s for s in _memory_sessions.values() if s.get("user_id")==user_id],
        key=lambda s:s.get("completed_at") or "")

@app.route("/user/<user_id>/analytics",methods=["GET"])
def user_analytics(user_id):
    """Real cross-material analytics — replaces the mock mastery
    trend/topic breakdown/stat cards on the Analytics page. Every number
    here is computed directly from this user's actual stored sessions,
    not seeded/fabricated data."""
    sessions=[s for s in _sessions_for_user(user_id) if s.get("status")=="complete"]

    # ── Overall mastery: average of each material's LATEST session score ──
    by_material={}
    for s in sessions:
        by_material[s.get("material_id")]=s  # sessions are already time-sorted, so last write wins = latest
    latest_scores=[s.get("score",0) for s in by_material.values()]
    overall_mastery_percent=round(100*sum(latest_scores)/len(latest_scores)) if latest_scores else 0

    # ── Problems solved: total questions answered across every session ──
    problems_solved=sum(len(s.get("answers") or []) for s in sessions)

    # ── Study time: sum of real per-question time_taken, converted to hours ──
    total_seconds=sum(a.get("time_taken",0) for s in sessions for a in (s.get("answers") or []))
    study_time_hours=round(total_seconds/3600,2)

    # ── Day streak: consecutive calendar days up to today with >=1 completed session ──
    days_with_activity=set()
    for s in sessions:
        ca=s.get("completed_at")
        if ca:
            try:days_with_activity.add(datetime.fromisoformat(ca).date())
            except Exception:pass
    streak=0
    cursor=datetime.utcnow().date()
    while cursor in days_with_activity:
        streak+=1;cursor=cursor-timedelta(days=1)

    # ── Mastery progress over time: one point per completed session, chronological ──
    mastery_trend=[{"label":f"S{i+1}","retentionPercent":round((s.get("score") or 0)*100),
        "highlighted":i==len(sessions)-1} for i,s in enumerate(sessions)]

    # ── Topic mastery: average correctness per topic, across every answer ever given ──
    topic_correct={};topic_total={}
    for s in sessions:
        for a in (s.get("answers") or []):
            t=a.get("topic") or "General"
            topic_total[t]=topic_total.get(t,0)+1
            if a.get("is_correct"):topic_correct[t]=topic_correct.get(t,0)+1
    topic_mastery=[{"topic":t,"masteryPercent":round(100*topic_correct.get(t,0)/topic_total[t]),
        "trend":"Stable"} for t in topic_total]
    topic_mastery.sort(key=lambda x:-x["masteryPercent"])

    return jsonify({
        "overallMasteryPercent":overall_mastery_percent,
        "problemsSolved":problems_solved,
        "studyTimeHours":study_time_hours,
        "currentStreakDays":streak,
        "masteryProgressTrend":mastery_trend,
        "topicMastery":topic_mastery[:8],
        "sessions_analyzed":len(sessions),
    })

@app.route("/user/<user_id>/materials",methods=["GET"])
def list_materials(user_id):
    """Powers the dashboard: every material this user has ever uploaded,
    persisted — never needs re-uploading. Each entry includes its own
    session count, coverage, and latest session's score/status so the
    dashboard can render separate progress per material without a second
    round-trip per item."""
    materials=_materials_for_user(user_id)
    out=[]
    for m in materials:
        sessions=_sessions_for_material(m["_id"])
        coverage=m.get("chunk_coverage",{})
        covered=sum(1 for v in coverage.values() if v>0)
        coverage_percent=round(100*covered/max(len(coverage),1),1)
        latest=sessions[-1] if sessions else None
        out.append({"material_id":m["_id"],"filename":m.get("filename","Untitled.pdf"),
            "uploaded_at":m.get("uploaded_at"),"difficulty_summary":m.get("difficulty_summary",{}),
            "mode":m.get("mode","fixed"),"study_days":m.get("study_days",7),
            "material_coverage_percent":coverage_percent,"session_count":len(sessions),
            "latest_session":None if not latest else {
                "session_id":latest["_id"],"session_number":latest.get("session_number"),
                "status":latest.get("status"),"score":latest.get("score"),
                "next_review_date":(latest.get("forgetting_curve") or {}).get("next_review_date"),
                "mastery_reached":(latest.get("forgetting_curve") or {}).get("mastery_reached",False),
                "completed_at":latest.get("completed_at")}})
    return jsonify({"materials":out,"total":len(out)})

@app.route("/user/<user_id>/sessions",methods=["GET"])
def list_user_sessions(user_id):
    """Every completed session this user has ever done, across every
    material, with the material's filename/topic context attached — powers
    the AI Feedback page's 'browse by session / by date' picker, so past
    feedback is actually reachable instead of only visible right after
    submitting."""
    sessions=[s for s in _sessions_for_user(user_id) if s.get("status")=="complete"]
    out=[]
    for s in sessions:
        material=_material_get(s.get("material_id")) or {}
        answers=s.get("answers") or []
        topics=list({a.get("topic") for a in answers if a.get("topic")})
        out.append({
            "session_id":s["_id"],"material_id":s.get("material_id"),
            "material_filename":material.get("filename","Untitled.pdf"),
            "session_number":s.get("session_number"),"score":s.get("score"),
            "completed_at":s.get("completed_at"),"question_count":len(answers),
            "topics":topics[:4],
            "mastery_reached":(s.get("forgetting_curve") or {}).get("mastery_reached",False),
        })
    out.sort(key=lambda x:x.get("completed_at") or "",reverse=True)
    return jsonify({"sessions":out,"total":len(out)})

@app.route("/material/<mid>/sessions",methods=["GET"])
def list_material_sessions(mid):
    """Every past session on one material — separate score, status, and
    forgetting-curve schedule per entry, for the per-material progress view
    (session history list + progress-over-time graph)."""
    if not _material_exists(mid):return jsonify({"error":"not found"}),404
    sessions=_sessions_for_material(mid)
    out=[{"session_id":s["_id"],"session_number":s.get("session_number"),"status":s.get("status"),
        "score":s.get("score"),"started_at":s.get("started_at"),"completed_at":s.get("completed_at"),
        "forgetting_curve":s.get("forgetting_curve"),"question_mix":s.get("question_mix")} for s in sessions]
    return jsonify({"sessions":out,"total":len(out)})

@app.route("/session/<sid>",methods=["GET"])
def get_session_detail(sid):
    """Full detail of one past (or in-progress) session — the 'separate
    result panel' per session: questions, answers, XAI, learner profile,
    forgetting curve, all as originally recorded for that specific attempt."""
    if not _session_exists(sid):return jsonify({"error":"not found"}),404
    s=_session_get(sid)
    return jsonify({"session_id":s["_id"],"material_id":s.get("material_id"),"session_number":s.get("session_number"),
        "status":s.get("status"),"score":s.get("score"),"started_at":s.get("started_at"),
        "completed_at":s.get("completed_at"),"questions":_strip(s.get("questions",[])),
        "answers":s.get("answers",[]),"learner_profile":s.get("learner_profile"),
        "forgetting_curve":s.get("forgetting_curve")})

@app.route("/material/<mid>/session/start",methods=["POST"])
def start_session(mid):
    """Starts a NEW session (quiz attempt) on an already-uploaded material.
    This is the ONLY way to get a 2nd/3rd/... session — no re-upload
    involved. The learner profile driving question difficulty/mix comes from
    the material's most recently COMPLETED session (if any), so session 2
    genuinely adapts to how session 1 went, not a blank slate."""
    if not _material_exists(mid):return jsonify({"error":"not found"}),404
    material=_material_get(mid)
    chunks=material["chunks"]

    prior_sessions=_sessions_for_material(mid)
    last_complete=next((s for s in reversed(prior_sessions) if s.get("status")=="complete"),None)
    if last_complete:
        profile=last_complete.get("learner_profile") or derive_learner_profile(last_complete)
    else:
        profile=derive_learner_profile({"answers":[],"chunks":chunks,"session_count":0})
    session_number=len(prior_sessions)+1
    profile["session_count"]=session_number

    coverage=material.get("chunk_coverage",{str(c["index"]):0 for c in chunks})
    ordered_chunks=_coverage_aware_chunk_order(chunks,coverage,profile)

    total_q=determine_question_count(len(chunks))
    easy_r,med_r,hard_r=determine_type_mix(profile)
    easy_n,med_n,hard_n=_distribute_counts(total_q,easy_r,med_r,hard_r)
    easy_n,med_n,hard_n=_cap_to_time_budget(easy_n,med_n,hard_n)
    total_q=easy_n+med_n+hard_n

    questions=None;used_gemini=False
    if GEMINI_WORKS is not False:
        try:
            prioritised=ordered_chunks[:max(total_q,len(ordered_chunks))]
            # Same fix as _xai_token_budget: a flat 16000-token cap was too
            # tight for ~14-15 questions worth of rich JSON (rationale,
            # hint, xai_explanation per question) once gemini-3.6-flash's
            # internal "thinking" tokens are accounted for — confirmed in
            # production logs ("Unterminated string...") truncating
            # mid-JSON and silently dropping to the offline fallback
            # generator, which is what produced garbled/nonsense questions
            # on scanned material. Model's real ceiling is 65536 (queried
            # from the API), so there's room for a generous budget.
            question_tok=min(60000,1400*total_q+6000)
            raw=call_gemini(build_model2_system_prompt(profile,easy_n,med_n,hard_n),build_question_user_prompt(prioritised),max_tokens=question_tok)
            data=parse_json_response(raw);questions=data.get("questions",[])
            for i,q in enumerate(questions):q["id"]=f"q{i+1}"
            used_gemini=True;log.info("[start] Gemini: %d Qs (easy=%d med=%d hard=%d)",len(questions),easy_n,med_n,hard_n)
        except RuntimeError as e:
            if"403"in str(e):log.warning("[start] Gemini 403 → using offline fallback generator. Google's actual reason: %s",e)
            else:log.error("[start] Gemini err (falling back — this session's questions/hints/XAI will be lower quality): %s",e)
        except Exception as e:log.error("[start] unexpected: %s",e)
    if not questions:
        questions=generate_questions_fallback(ordered_chunks,profile,easy_n,med_n,hard_n)
        log.info("[start] Fallback: %d Qs (easy=%d med=%d hard=%d)",len(questions),easy_n,med_n,hard_n)

    for q in questions:
        q.setdefault("time_allotted_seconds",TIME_ALLOTMENT.get(q.get("question_type","easy"),90))

    # ── verify every question is actually grounded in the uploaded material
    #    (not generic drift), and stamp Model 1's real per-chunk difficulty
    #    output onto each question so it's independently checkable ──
    nd,nl=_next_difficulty(profile)
    relevance_check=verify_and_repair_grounding(questions,chunks,nd,nl,used_gemini)
    for q in questions:_clean_question_text_fields(q)

    # ── update per-chunk coverage on the MATERIAL (not the session) so it
    #    persists across every session on this document ──
    for q in questions:
        ci=str(q.get("chunk_index",""))
        if ci in coverage:coverage[ci]=coverage.get(ci,0)+1
    covered_count=sum(1 for v in coverage.values() if v>0)
    coverage_percent=round(100*covered_count/max(len(coverage),1),1)
    _material_update(mid,{"chunk_coverage":coverage,"session_count":session_number})

    sid=str(uuid.uuid4())
    _session_save(sid,{"id":sid,"material_id":mid,"user_id":material.get("user_id"),
        "session_number":session_number,"questions":questions,"answers":[],"status":"active",
        "started_at":datetime.utcnow().isoformat(),"question_mix":{"easy":easy_n,"medium":med_n,"hard":hard_n},
        "learner_profile":profile})
    return jsonify({"session_id":sid,"material_id":mid,"session_number":session_number,
        "questions":_strip(questions),"total":len(questions),"adapted_diff":profile["avg_difficulty_score"],
        "pace":profile["preferred_pace"],"used_gemini":used_gemini,
        "question_mix":{"easy":easy_n,"medium":med_n,"hard":hard_n},
        "material_coverage_percent":coverage_percent,
        "relevance_check":relevance_check})

@app.route("/session/<sid>/question/<qid>/hint",methods=["POST"])
def get_hint(sid,qid):
    if not _session_exists(sid):return jsonify({"error":"not found"}),404
    session=_session_get(sid)
    q=next((qq for qq in session.get("questions",[]) if qq["id"]==qid),None)
    if not q:return jsonify({"error":"question not found"}),404

    body=request.get_json() or{}
    level=int(body.get("hint_level",1))
    level=max(1,min(MAX_HINT_LEVEL,level))
    current_answer=body.get("current_answer","")

    hint_text=None
    if GEMINI_WORKS is not False:
        try:
            # 600 could leave near-zero room for the actual hint once
            # gemini-3.6-flash's internal "thinking" tokens are subtracted
            # from the same budget (see _xai_token_budget for the full
            # explanation) — 2000 keeps this cheap while giving real headroom.
            hint_text=call_gemini("You are a maths tutor giving one short progressive hint.",
                build_hint_prompt(q,level,current_answer),max_tokens=2000).strip()
        except Exception as e:
            log.warning("[hint] Gemini failed, using fallback: %s",e)
    if not hint_text:
        hint_text=generate_fallback_hint(q,level,current_answer)
    hint_text=_clean_math_notation(hint_text)

    return jsonify({"question_id":qid,"hint_level":level,"hint_text":hint_text,"hints_remaining":MAX_HINT_LEVEL-level})

def build_batch_xai_prompt(items):
    """One prompt covering EVERY question in this submission, instead of
    one Gemini call per question. This is the actual fix for hitting
    free-tier rate limits mid-session: a 15-question session used to make
    15 separate round-trips just for XAI (on top of question generation and
    any hints already used) — now it's exactly one."""
    blocks=[]
    for it in items:
        blocks.append(
            f"QUESTION {it['qid']} ({it['fmt']}): {it['question_text']}\n"
            f"STUDENT ANSWER: {json.dumps(it['answer_summary'],default=str)}\n"
            f"RESULT: {'CORRECT' if it['is_correct'] else 'INCORRECT/PARTIAL'}\n"
            f"TIME: {it['tt']:.0f}s of {it['allotted']:.0f}s · HINTS: {len(it['hints_used'])}"
        )
    joined="\n\n".join(blocks)
    return f"""You are an XAI tutor for Nuromathix. Below are {len(items)} questions from
ONE student's just-completed session. For EACH question, write feedback (150-220 words):
1. {"Confirm why correct and deepen the concept" if False else "If correct: confirm why and deepen the concept. If incorrect: explain the FULL correct step-by-step solution with numbered steps."}
2. If incorrect, name the likely mistake pattern (sign error, wrong formula, arithmetic slip, etc).
3. One memory trick or conceptual anchor.
4. One brief comment on time/hint usage.
5. A short encouraging close.

FORMATTING: plain text only, not LaTeX — never use $ or $$ delimiters;
write exponents as x^2 or x² and fractions as a/b, never \frac{{a}}{{b}}.

{joined}

Return ONLY this JSON object, one entry per question, in the same order:
{{"feedback":[{{"question_id":"{items[0]['qid'] if items else 'q1'}","xai_text":"...","confidence_boost":0.1-1.0,"review_topics":["t1"]}}]}}"""

def _xai_token_budget(n_items):
    # gemini-3.6-flash spends real, variable tokens on internal "thinking"
    # BEFORE writing the visible JSON answer (confirmed via usageMetadata —
    # a 14-item batch used ~2200 thinking tokens on top of the visible
    # output). The old 700/item + 800 budget left too little headroom: on a
    # long/detailed real prompt, thinking alone could consume the entire
    # cap, leaving ZERO characters for the actual answer — an empty string
    # that fails to parse as JSON (confirmed in production logs: "Expecting
    # value: line 1 column 1"). The model's real ceiling is 65536 output
    # tokens (queried from the API), so there's ample room for a generous
    # fixed thinking buffer instead of guessing at a thinkingConfig field
    # this model rejects outright (tested: thinkingBudget=0 -> HTTP 400).
    return min(60000,1200*n_items+6000)

def _call_batch_xai_once(items):
    """One batch Gemini call for exactly these items. Raises on any
    failure (network, HTTP, empty/unparseable response) — callers decide
    how to retry or fall back."""
    raw=call_gemini("You are an XAI tutor. Be precise and encouraging.",
        build_batch_xai_prompt(items),max_tokens=_xai_token_budget(len(items)))
    parsed=parse_json_response(raw)
    out={}
    for f in parsed.get("feedback",[]):
        qid=f.get("question_id")
        if qid:out[qid]={"xai_text":f.get("xai_text",""),
            "confidence_boost":f.get("confidence_boost",0.5),
            "review_topics":f.get("review_topics",[])}
    return out

def generate_batch_xai(items):
    """Returns {question_id: {xai_text,...}} for as many items as Gemini
    successfully covers. Tries ONE call for everything first; if that
    fails (often a token-budget/truncation issue on large sessions — see
    _xai_token_budget), retries by SPLITTING into two smaller batches,
    which need much less budget each and are far less likely to truncate.
    Only items still missing after that fall back individually via
    generate_xai_fallback at the call site — never blocks the submit."""
    if not items or GEMINI_WORKS is False:
        return {}
    try:
        return _call_batch_xai_once(items)
    except Exception as e:
        log.warning("[xai] full batch (%d questions) failed, retrying as two smaller batches: %s",len(items),e)
    if len(items)<2:
        return {}
    mid=len(items)//2
    out={}
    for half in (items[:mid],items[mid:]):
        try:
            out.update(_call_batch_xai_once(half))
        except Exception as e:
            log.warning("[xai] split batch (%d questions) also failed, those fall back individually: %s",len(half),e)
    return out

@app.route("/session/<sid>/submit",methods=["POST"])
def submit_answers(sid):
    if not _session_exists(sid):return jsonify({"error":"not found"}),404
    session=_session_get(sid);qs=session.get("questions",[]);body=request.get_json() or{}
    user_ans=body.get("answers",[]);qmap={q["id"]:q for q in qs}

    # ── Phase 1: grade every answer first — no Gemini calls yet ──
    graded=[]
    for ua in user_ans:
        qid=ua.get("question_id");q=qmap.get(qid)
        if not q:continue
        fmt=q.get("format","fill_blank")
        tt=float(ua.get("time_taken",30.0))
        allotted=q.get("time_allotted_seconds",TIME_ALLOTMENT.get(q.get("question_type","easy"),90))
        timed_out=bool(ua.get("timed_out",False))
        overtime=float(ua.get("overtime_seconds",0.0))
        continued_after_timeout=bool(ua.get("continued_after_timeout",False))
        hints_used=ua.get("hints_used",[])
        is_correct,answer_summary,score=grade_answer(q,ua)
        graded.append({"qid":qid,"q":q,"fmt":fmt,"question_text":q.get("question_text",""),
            "tt":tt,"allotted":allotted,"timed_out":timed_out,"overtime":overtime,
            "continued_after_timeout":continued_after_timeout,"hints_used":hints_used,
            "is_correct":is_correct,"answer_summary":answer_summary,"score":score})

    # ── Phase 2: ONE Gemini call for every question's XAI, not one-per-question ──
    batch_xai=generate_batch_xai(graded)

    # ── Phase 3: build the results the frontend actually receives ──
    results=[]
    for g in graded:
        qid=g["qid"];q=g["q"];fmt=g["fmt"]
        xai=batch_xai.get(qid)
        if not xai:xai=generate_xai_fallback(q,g["is_correct"],g["answer_summary"])
        if xai.get("xai_text"):xai["xai_text"]=_clean_math_notation(xai["xai_text"])

        # ── the correct answer, revealed only now that the question is
        #    graded — the frontend results/XAI screen needs this to show
        #    "your answer" vs "correct answer" per format ──
        if fmt=="fill_blank":
            opts=q.get("options",[]);ci=q.get("correct_index")
            correct_answer={"options":opts,"correct_index":ci,
                "correct_text":opts[ci] if ci is not None and 0<=ci<len(opts) else None}
        elif fmt=="short_answer":
            correct_answer={"expected_answer":q.get("expected_answer")}
        else:
            correct_answer={"sub_parts":[{"id":sp.get("id"),"prompt":sp.get("prompt"),
                "expected_answer":sp.get("expected_answer")} for sp in q.get("sub_parts",[])]}

        results.append({"question_id":qid,"question_text":q.get("question_text",""),"format":fmt,
            "question_type":q.get("question_type","easy"),"topic":q.get("topic",""),"topic_tags":q.get("topic_tags",[]),
            "difficulty_score":q.get("difficulty_score",3),"difficulty_level":q.get("difficulty_level","medium"),
            "model1_difficulty_score":q.get("model1_difficulty_score"),"model1_difficulty_level":q.get("model1_difficulty_level"),
            "model1_confidence":q.get("model1_confidence"),"model1_source":q.get("model1_source"),
            "answer":g["answer_summary"],"correct_answer":correct_answer,"is_correct":g["is_correct"],"score":g["score"],
            "time_taken":g["tt"],"time_allotted_seconds":g["allotted"],"timed_out":g["timed_out"],
            "overtime_seconds":g["overtime"],"continued_after_timeout":g["continued_after_timeout"],
            "hints_used":g["hints_used"],"xai":xai})

    session["answers"]=results
    fp=derive_learner_profile(session);fp["session_count"]=session.get("session_number",1)
    material=_material_get(session.get("material_id")) or {}
    curve=compute_forgetting_curve(fp,mode=material.get("mode","fixed"),study_days=material.get("study_days",7))
    total=len(results);correct=sum(1 for r in results if r["is_correct"])
    overall_score=(sum(r["score"] for r in results)/total) if total else 0.0

    _session_update(sid,{"answers":results,"status":"complete","completed_at":datetime.utcnow().isoformat(),
        "learner_profile":fp,"forgetting_curve":curve,"score":round(overall_score,3)})

    # Mastery needs the full session history INCLUDING this just-completed
    # one, so it's computed only after the save above, not before.
    curve["mastery_reached"]=compute_mastery(session.get("material_id"),curve["stability"],curve["session_cap"])
    _session_update(sid,{"forgetting_curve":curve})

    log.info("[submit] sid=%s score=%.0f%% timeouts=%s mastery=%s",sid,overall_score*100,fp.get("timeout_rate"),curve["mastery_reached"])
    return jsonify({"session_id":sid,"material_id":session.get("material_id"),
        "session_number":session.get("session_number"),"score":round(overall_score,3),
        "correct":correct,"total":total,"results":results,
        "learner_profile":fp,"forgetting_curve":curve,"next_review_date":curve["next_review_date"],
        "next_review_days":curve["next_review_days"],"mastery_reached":curve["mastery_reached"],
        "session_cap":curve["session_cap"]})

@app.route("/session/<sid>/questions",methods=["GET"])
def get_questions(sid):
    if not _session_exists(sid):return jsonify({"error":"not found"}),404
    qs=_strip(_session_get(sid).get("questions",[]))
    return jsonify({"questions":qs,"total":len(qs)})

if __name__=="__main__":
    app.run(host="0.0.0.0",port=5000,debug=True)