// Either phone: refresh its FCM token; the maid phone can also set its language.
// body: { device_id, fcm_token?, lang? ('en' | 'kn') }
import { handle } from "../_shared/http.ts";
import { must } from "../_shared/db.ts";
import { anyCtx } from "../_shared/auth.ts";

handle(async (body) => {
  const ctx = await anyCtx(body);
  if (ctx.role === "owner") {
    if (body.fcm_token) {
      must(await ctx.sb.from("house").update({ owner_fcm_token: body.fcm_token }).eq("id", ctx.house.id));
    }
    return { role: "owner" };
  }
  const patch: Record<string, unknown> = {};
  if (body.fcm_token) patch.fcm_token = body.fcm_token;
  if (body.lang === "en" || body.lang === "kn") patch.lang = body.lang;
  if (Object.keys(patch).length) {
    must(await ctx.sb.from("cook_device").update(patch).eq("id", ctx.cook!.id));
  }
  return { role: "maid", house_name: ctx.house.name, name: ctx.cook!.name };
});
