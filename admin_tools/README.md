# NeuroMathix teacher-account administration

Public sign-up creates **students only**. Teacher accounts must be approved and
created with the Firebase Admin SDK.

## Setup

```bash
cd admin_tools
python -m venv .venv
# Windows: .venv\Scripts\activate
# macOS/Linux: source .venv/bin/activate
pip install -r requirements.txt
```

Download a Firebase service-account key from the Firebase/Google Cloud console,
store it outside this repository, and run:

```bash
python create_teacher.py \
  --service-account /secure/path/service-account.json \
  --email teacher@example.com \
  --password "StrongPassword123!" \
  --first-name Chameera \
  --last-name "De Silva" \
  --institution "SITC Campus"
```

Never commit a service-account key to Git.
