import { initializeApp } from "firebase-admin/app";
import {
  FieldValue,
  Timestamp,
  getFirestore,
} from "firebase-admin/firestore";
import { logger } from "firebase-functions";
import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { onSchedule } from "firebase-functions/v2/scheduler";

initializeApp();
const db = getFirestore();

const activeReviewStatuses = new Set([
  "scheduled",
  "available",
  "rescheduled",
]);

function asDate(value: unknown): Date | null {
  if (value instanceof Timestamp) return value.toDate();
  if (value instanceof Date) return value;
  if (typeof value === "string") {
    const parsed = new Date(value);
    return Number.isNaN(parsed.getTime()) ? null : parsed;
  }
  return null;
}

function asNumber(value: unknown, fallback = 0): number {
  return typeof value === "number" && Number.isFinite(value)
    ? value
    : fallback;
}

function activeSchedule(data: Record<string, unknown>): boolean {
  return activeReviewStatuses.has(String(data.status ?? "scheduled"));
}

function riskFrom({
  mastery,
  retention,
  overdue,
  pendingHelp,
  inactiveDays,
}: {
  mastery: number;
  retention: number;
  overdue: number;
  pendingHelp: number;
  inactiveDays: number;
}): { level: "urgent" | "reviewSoon" | "safe"; reasons: string[] } {
  const reasons: string[] = [];

  if (mastery < 50) reasons.push(`Mastery is low (${Math.round(mastery)}%).`);
  else if (mastery < 70) reasons.push(`Mastery needs improvement (${Math.round(mastery)}%).`);

  if (retention < 40) reasons.push(`Predicted retention is critical (${Math.round(retention)}%).`);
  else if (retention < 65) reasons.push(`Predicted retention is falling (${Math.round(retention)}%).`);

  if (overdue >= 2) reasons.push(`${overdue} review sessions are overdue.`);
  else if (overdue === 1) reasons.push("One review session is overdue.");

  if (pendingHelp > 0) {
    reasons.push(`${pendingHelp} teacher-help request${pendingHelp === 1 ? " is" : "s are"} pending.`);
  }

  if (inactiveDays >= 7) reasons.push(`No recorded activity for ${inactiveDays} days.`);

  if (mastery < 50 || retention < 40 || overdue >= 2 || inactiveDays >= 14) {
    return { level: "urgent", reasons };
  }
  if (
    mastery < 70 ||
    retention < 65 ||
    overdue === 1 ||
    pendingHelp > 0 ||
    inactiveDays >= 7
  ) {
    return { level: "reviewSoon", reasons };
  }
  return {
    level: "safe",
    reasons: reasons.length > 0 ? reasons : ["Performance and review activity are stable."],
  };
}

async function rebuildStudentSummary(studentId: string): Promise<void> {
  const userRef = db.collection("users").doc(studentId);
  const summaryRef = db.collection("teacherStudentSummaries").doc(studentId);
  const userSnapshot = await userRef.get();

  if (!userSnapshot.exists) {
    await summaryRef.delete().catch(() => undefined);
    return;
  }

  const user = userSnapshot.data() ?? {};
  const teacherId = String(user.teacherId ?? "").trim();
  if (!teacherId) {
    await summaryRef.delete().catch(() => undefined);
    return;
  }

  const [scheduleSnapshot, helpSnapshot, dashboardSnapshot, previousSummary] =
    await Promise.all([
      db.collection("reviewSchedules").where("studentId", "==", studentId).get(),
      db.collection("helpRequests").where("studentId", "==", studentId).get(),
      db.collection("student_dashboards").doc(studentId).get(),
      summaryRef.get(),
    ]);

  const now = new Date();
  const schedules: Array<{ id: string; [key: string]: unknown }> =
    scheduleSnapshot.docs.map((doc) => ({
      id: doc.id,
      ...doc.data(),
    }));

  const active = schedules
    .filter(activeSchedule)
    .sort((a, b) => {
      const left = asDate(a.scheduledAt)?.getTime() ?? Number.MAX_SAFE_INTEGER;
      const right = asDate(b.scheduledAt)?.getTime() ?? Number.MAX_SAFE_INTEGER;
      return left - right;
    });

  const overdueReviews = active.filter((schedule) => {
    const date = asDate(schedule.scheduledAt);
    return date != null && date.getTime() < now.getTime();
  }).length;

  const completedReviews = schedules.filter(
    (schedule) => String(schedule.status) === "completed",
  ).length;

  const pendingHelpRequests = helpSnapshot.docs.filter((doc) => {
    const status = String(doc.data().status ?? "pending");
    return status === "pending" || status === "viewed";
  }).length;

  const dashboard = dashboardSnapshot.data() ?? {};
  const oldSummary = previousSummary.data() ?? {};
  const nextSchedule = active[0];
  const latestSchedule = [...schedules].sort((a, b) => {
    const left = asDate(a.updatedAt ?? a.createdAt ?? a.scheduledAt)?.getTime() ?? 0;
    const right = asDate(b.updatedAt ?? b.createdAt ?? b.scheduledAt)?.getTime() ?? 0;
    return right - left;
  })[0];

  const hasLearningData = dashboardSnapshot.exists || schedules.length > 0;
  const mastery = asNumber(
    dashboard.overallMasteryPercent,
    asNumber(latestSchedule?.masteryScore, asNumber(oldSummary.masteryPercent, 0)),
  );
  const rawScheduleRetention = latestSchedule == null
    ? asNumber(oldSummary.retentionPercent, 0)
    : asNumber(latestSchedule.predictedRetention, 0);
  const retention = asNumber(
    dashboard.retentionPercent,
    latestSchedule != null && rawScheduleRetention <= 1
      ? rawScheduleRetention * 100
      : rawScheduleRetention,
  );

  const lastActiveAt =
    asDate(dashboard.lastActiveAt) ??
    asDate(oldSummary.lastActiveAt) ??
    asDate(user.lastLoginAt) ??
    asDate(user.createdAt) ??
    now;
  const inactiveDays = Math.max(
    0,
    Math.floor((now.getTime() - lastActiveAt.getTime()) / 86_400_000),
  );

  const risk = hasLearningData
    ? riskFrom({
        mastery,
        retention,
        overdue: overdueReviews,
        pendingHelp: pendingHelpRequests,
        inactiveDays,
      })
    : {
        level: "reviewSoon" as const,
        reasons: ["No learning-session data has been recorded yet."],
      };

  await summaryRef.set(
    {
      studentId,
      teacherId,
      displayName: user.displayName ?? user.email ?? "Student",
      email: user.email ?? "",
      currentTopic:
        nextSchedule?.conceptName ??
        latestSchedule?.conceptName ??
        oldSummary.currentTopic ??
        "No active topic",
      masteryPercent: Math.round(Math.max(0, Math.min(100, mastery))),
      retentionPercent: Math.round(Math.max(0, Math.min(100, retention))),
      overdueReviews,
      pendingHelpRequests,
      completedReviews,
      nextReviewAt: nextSchedule?.scheduledAt ?? null,
      lastActiveAt: Timestamp.fromDate(lastActiveAt),
      riskLevel: risk.level,
      riskReasons: risk.reasons,
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
}

async function createNotificationOnce(
  id: string,
  data: Record<string, unknown>,
): Promise<void> {
  const reference = db.collection("notifications").doc(id);
  await db.runTransaction(async (transaction) => {
    const existing = await transaction.get(reference);
    if (!existing.exists) {
      transaction.create(reference, {
        ...data,
        isRead: false,
        createdAt: FieldValue.serverTimestamp(),
      });
    }
  });
}

export const activateDueReviews = onSchedule(
  {
    schedule: "every 15 minutes",
    timeZone: "Asia/Colombo",
    region: "asia-south1",
  },
  async () => {
    const now = Timestamp.now();
    const dueSnapshot = await db
      .collection("reviewSchedules")
      .where("scheduledAt", "<=", now)
      .limit(300)
      .get();

    const reminderSnapshot = await db
      .collection("reviewSchedules")
      .where("reminderAt", "<=", now)
      .limit(300)
      .get();

    const tasks: Promise<unknown>[] = [];

    for (const document of dueSnapshot.docs) {
      const data = document.data();
      if (!activeSchedule(data) || data.status === "available") continue;

      tasks.push(
        document.ref.update({
          status: "available",
          availableAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        }),
      );
      tasks.push(
        createNotificationOnce(`review_due_${document.id}`, {
          userId: data.studentId,
          type: "review_due",
          title: "Time to Review",
          message: `${data.conceptName ?? "Your mathematics topic"} is ready for review.`,
          relatedScheduleId: document.id,
        }),
      );
    }

    for (const document of reminderSnapshot.docs) {
      const data = document.data();
      const scheduledAt = asDate(data.scheduledAt);
      if (
        !activeSchedule(data) ||
        data.reminderSentAt != null ||
        scheduledAt == null ||
        scheduledAt.getTime() <= now.toDate().getTime()
      ) {
        continue;
      }

      tasks.push(
        document.ref.update({
          reminderSentAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        }),
      );
      tasks.push(
        createNotificationOnce(`review_reminder_${document.id}`, {
          userId: data.studentId,
          type: "review_reminder",
          title: "Upcoming Review",
          message: `${data.conceptName ?? "Your mathematics topic"} is scheduled soon.`,
          relatedScheduleId: document.id,
        }),
      );
    }

    await Promise.all(tasks);
    logger.info("Review scheduler completed", { operations: tasks.length });
  },
);

export const markOverdueReviews = onSchedule(
  {
    schedule: "every day 01:00",
    timeZone: "Asia/Colombo",
    region: "asia-south1",
  },
  async () => {
    const cutoff = Timestamp.fromDate(new Date(Date.now() - 24 * 60 * 60 * 1000));
    const snapshot = await db
      .collection("reviewSchedules")
      .where("scheduledAt", "<=", cutoff)
      .limit(300)
      .get();

    const tasks: Promise<unknown>[] = [];
    for (const document of snapshot.docs) {
      const data = document.data();
      if (!activeSchedule(data)) continue;
      tasks.push(
        document.ref.update({
          status: "missed",
          missedAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        }),
      );
      tasks.push(
        createNotificationOnce(`review_missed_${document.id}`, {
          userId: data.studentId,
          type: "review_missed",
          title: "Review Overdue",
          message: `${data.conceptName ?? "A mathematics review"} is overdue. Start it as soon as possible.`,
          relatedScheduleId: document.id,
        }),
      );
    }
    await Promise.all(tasks);
  },
);

export const onReviewScheduleChanged = onDocumentWritten(
  {
    document: "reviewSchedules/{scheduleId}",
    region: "asia-south1",
  },
  async (event) => {
    const studentId = String(
      event.data?.after.data()?.studentId ??
        event.data?.before.data()?.studentId ??
        "",
    );
    if (studentId) await rebuildStudentSummary(studentId);
  },
);

export const onHelpRequestChanged = onDocumentWritten(
  {
    document: "helpRequests/{requestId}",
    region: "asia-south1",
  },
  async (event) => {
    const studentId = String(
      event.data?.after.data()?.studentId ??
        event.data?.before.data()?.studentId ??
        "",
    );
    if (studentId) await rebuildStudentSummary(studentId);
  },
);

export const onDashboardChanged = onDocumentWritten(
  {
    document: "student_dashboards/{studentId}",
    region: "asia-south1",
  },
  async (event) => {
    const studentId = event.params.studentId;
    if (studentId) await rebuildStudentSummary(studentId);
  },
);

export const onUserChanged = onDocumentWritten(
  {
    document: "users/{studentId}",
    region: "asia-south1",
  },
  async (event) => {
    const before = event.data?.before.data() ?? {};
    const after = event.data?.after.data() ?? {};
    if (
      before.teacherId !== after.teacherId ||
      before.displayName !== after.displayName ||
      before.lastLoginAt !== after.lastLoginAt
    ) {
      await rebuildStudentSummary(event.params.studentId);
    }
  },
);
