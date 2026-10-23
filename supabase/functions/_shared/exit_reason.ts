// Builds an anonymous exit_reasons row from an optional {reason, other} body, or null when nothing was answered.
export const REASONS = ["got_what_i_needed", "too_expensive", "didnt_find_my_vc", "data_not_useful", "other"];

export function exitReason(body: unknown, kind: "cancel" | "delete", plan: unknown): Record<string, unknown> | null {
  const b = (body && typeof body === "object" ? body : {}) as Record<string, unknown>;
  const reason = typeof b.reason === "string" && REASONS.includes(b.reason) ? b.reason : null;
  const other = typeof b.other === "string" ? b.other.trim().slice(0, 500) : "";
  if (!reason && !other) return null;
  return { kind, reason, other_text: other || null, plan: typeof plan === "string" ? plan : null };
}
