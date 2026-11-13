-- Run once in Supabase: SQL Editor > New query > paste > Run
-- Lets the app get live events (for the banners that drop from the top).

do $$
begin
  begin alter publication supabase_realtime add table public.messages; exception when others then null; end;
  begin alter publication supabase_realtime add table public.likes; exception when others then null; end;
  begin alter publication supabase_realtime add table public.reposts; exception when others then null; end;
  begin alter publication supabase_realtime add table public.comments; exception when others then null; end;
end $$;
