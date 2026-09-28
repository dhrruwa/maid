// Monthly payment slip as a PDF, stored in the private "slips" bucket.
import { PDFDocument, rgb, StandardFonts } from "npm:pdf-lib@1.17.1";
import { Ctx } from "./auth.ts";
import { MonthSummary, SlotInfo } from "./pay.ts";
import { monthLabel, shortDate } from "./time.ts";

const DOW = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

// Standard PDF fonts have no ₹ glyph, so slips use "Rs."
const rs = (n: number) => `Rs. ${n.toLocaleString("en-IN")}`;

function slotText(i: SlotInfo): string {
  switch (i.state) {
    case "done":
      return `Done${i.attendance?.is_manual ? " (manual)" : i.attendance?.is_offline ? " (offline)" : ""}`;
    case "missed":
      return "Missed";
    case "holiday_paid":
      return "Holiday (paid)";
    case "holiday_unpaid":
      return "Holiday (unpaid)";
    case "leave_paid":
      return "Leave (paid)";
    case "leave_unpaid":
      return "Leave (unpaid)";
    case "not_needed":
      return "-";
    case "pending":
    case "upcoming":
      return "Upcoming";
    default:
      return "";
  }
}

export async function buildSlipPdf(s: MonthSummary): Promise<Uint8Array> {
  const pdf = await PDFDocument.create();
  const font = await pdf.embedFont(StandardFonts.Helvetica);
  const bold = await pdf.embedFont(StandardFonts.HelveticaBold);
  const accent = rgb(0.91, 0.45, 0.13);
  const grey = rgb(0.4, 0.4, 0.4);
  const green = rgb(0.1, 0.55, 0.25);
  const red = rgb(0.8, 0.15, 0.15);

  let page = pdf.addPage([595, 842]); // A4
  let y = 800;
  const L = 40;
  const text = (t: string, x: number, size = 10, f = font, color = rgb(0, 0, 0)) =>
    page.drawText(t, { x, y, size, font: f, color });

  text("Payment slip", L, 22, bold, accent);
  y -= 26;
  text(monthLabel(s.month), L, 14, bold);
  const paid = s.payment;
  text(paid ? `PAID on ${shortDate(paid.paid_on)} ${paid.paid_on.slice(0, 4)}` : "NOT PAID YET", 400, 12, bold, paid ? green : red);
  y -= 22;
  text(`House: ${s.house_name}`, L, 11);
  y -= 15;
  text(`Cook: ${s.maid_name ?? "-"}`, L, 11);
  y -= 15;
  text(
    `Rates: weekday Rs.${s.rates.weekday_rate}/visit, weekend Rs.${s.rates.weekend_rate}/visit (morning only)`,
    L,
    9,
    font,
    grey,
  );
  y -= 22;

  // Table
  const cols = [L, 110, 160, 300, 440];
  const header = () => {
    page.drawRectangle({ x: L - 4, y: y - 4, width: 523, height: 16, color: rgb(0.98, 0.93, 0.87) });
    ["Date", "Day", "Morning", "Evening", "Amount"].forEach((h, i) => text(h, cols[i], 9, bold));
    y -= 16;
  };
  header();
  for (const d of s.days) {
    if (y < 150) {
      page = pdf.addPage([595, 842]);
      y = 800;
      header();
    }
    if (d.slots.morning.state === "none" && d.slots.evening.state === "none") continue;
    text(shortDate(d.date), cols[0], 9);
    text(DOW[d.dow], cols[1], 9);
    text(slotText(d.slots.morning), cols[2], 9);
    text(slotText(d.slots.evening), cols[3], 9);
    text(d.amount ? rs(d.amount) : "-", cols[4], 9);
    y -= 13;
  }

  y -= 12;
  page.drawLine({ start: { x: L, y: y + 6 }, end: { x: 555, y: y + 6 }, thickness: 0.5, color: grey });
  y -= 8;
  const c = s.counts, t = s.totals;
  const lines: [string, string][] = [
    ["Visits done", String(c.visits_done)],
    ["Missed visits", String(c.missed)],
    ["Full days / half days", `${c.full_days} / ${c.half_days}`],
    ["Holidays / leaves (days)", `${c.holidays} / ${c.leaves}`],
    [`Weekday visits x Rs.${s.rates.weekday_rate}`, `${c.weekday_visits} = ${rs(t.weekday_amount)}`],
    [`Weekend visits x Rs.${s.rates.weekend_rate}`, `${c.weekend_visits} = ${rs(t.weekend_amount)}`],
    ["Paid holidays / leave", `${c.paid_off_slots} = ${rs(t.paid_off_amount)}`],
  ];
  for (const [k, v] of lines) {
    text(k, L, 10);
    text(v, 360, 10);
    y -= 14;
  }
  y -= 6;
  text("Total", L, 14, bold);
  text(rs(paid ? paid.total_amount : t.earned), 360, 14, bold, accent);
  y -= 24;

  const offs = [
    ...s.holidays.map((h) =>
      `${shortDate(h.date)}: Holiday (${h.slot}, ${h.paid ? "paid" : "unpaid"})${h.note ? ` - ${h.note}` : ""}`
    ),
    ...s.leaves.filter((l) => l.status !== "pending").map((l) =>
      `${shortDate(l.date)}: Leave (${l.slot}, ${l.status.replace("_", " ")})${l.reason ? ` - ${l.reason}` : ""}`
    ),
  ];
  if (offs.length && y > 60) {
    text("Holidays and leaves", L, 10, bold);
    y -= 14;
    for (const o of offs) {
      if (y < 40) break;
      text(o.slice(0, 100), L, 8, font, grey);
      y -= 11;
    }
  }

  page.drawText(`Generated ${new Date().toISOString().slice(0, 10)}`, {
    x: L,
    y: 20,
    size: 7,
    font,
    color: grey,
  });
  return await pdf.save();
}

/** Builds, uploads (overwriting) and returns the storage path + a 1-hour signed URL. */
export async function storeSlip(ctx: Ctx, s: MonthSummary) {
  const bytes = await buildSlipPdf(s);
  const path = `${ctx.house.id}/${s.month}.pdf`;
  const up = await ctx.sb.storage.from("slips").upload(path, bytes, {
    contentType: "application/pdf",
    upsert: true,
  });
  if (up.error) throw new Error(`Slip upload failed: ${up.error.message}`);
  const signed = await ctx.sb.storage.from("slips").createSignedUrl(path, 3600, {
    download: `payslip-${s.month}.pdf`,
  });
  if (signed.error) throw new Error(signed.error.message);
  return { path, url: signed.data.signedUrl };
}
