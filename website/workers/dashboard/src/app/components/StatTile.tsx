import { Card, CardTitle } from "./ui/card";

export function StatTile({ label, value, suffix }: { label: string; value: string; suffix?: string }) {
  return (
    <Card>
      <CardTitle>{label}</CardTitle>
      <div className="mt-2 font-mono text-3xl font-semibold" style={{ color: "var(--color-primary)" }}>
        {value}
        {suffix && <span className="text-lg" style={{ color: "var(--color-muted)" }}>{suffix}</span>}
      </div>
    </Card>
  );
}
