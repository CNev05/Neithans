create type public.app_role as enum ('owner', 'superadmin');
create type public.payment_status as enum ('Pending', 'Paid', 'Overdue');
create type public.sms_status as enum ('queued', 'sent', 'failed');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  display_name text,
  phone text,
  role public.app_role not null default 'owner',
  permissions text[] not null default '{}',
  disabled boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.properties (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete restrict,
  name text not null,
  address text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.rooms (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete restrict,
  property_id uuid references public.properties(id) on delete set null,
  name text not null,
  category text,
  capacity integer not null default 0 check (capacity >= 0),
  current_occupancy integer not null default 0 check (current_occupancy >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.tenants (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete restrict,
  room_id uuid references public.rooms(id) on delete set null,
  name text not null,
  phone text,
  unit text,
  added_at date,
  endo_date date,
  next_due_date date,
  monthly_rent numeric(12,2) not null default 0 check (monthly_rent >= 0),
  advance_deposit numeric(12,2) not null default 0 check (advance_deposit >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.payments (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete restrict,
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  month integer not null check (month between 1 and 12),
  year integer not null check (year between 2000 and 2200),
  amount numeric(12,2) not null check (amount >= 0),
  status public.payment_status not null default 'Pending',
  category text,
  paid_at date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.sms_queue (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid references public.profiles(id) on delete set null,
  tenant_id uuid references public.tenants(id) on delete set null,
  recipient text not null,
  body text not null check (char_length(body) between 1 and 918),
  template text,
  status public.sms_status not null default 'queued',
  provider_message_id text,
  error text,
  scheduled_at timestamptz not null default now(),
  sent_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.audit_logs (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid references public.profiles(id) on delete set null,
  action text not null,
  resource text not null,
  resource_id uuid,
  metadata jsonb not null default '{}',
  created_at timestamptz not null default now()
);

create index rooms_owner_id_idx on public.rooms(owner_id);
create index tenants_owner_id_idx on public.tenants(owner_id);
create index payments_owner_period_idx on public.payments(owner_id, year, month);
create index payments_tenant_period_idx on public.payments(tenant_id, year, month);
create index sms_queue_status_schedule_idx on public.sms_queue(status, scheduled_at);
create index audit_logs_created_at_idx on public.audit_logs(created_at desc);

create or replace function public.is_superadmin()
returns boolean language sql stable security definer set search_path = public
as $$ select exists (select 1 from public.profiles where id = auth.uid() and role = 'superadmin' and disabled = false) $$;

create or replace function public.is_owner()
returns boolean language sql stable security definer set search_path = public
as $$ select exists (select 1 from public.profiles where id = auth.uid() and role = 'owner' and disabled = false) $$;

alter table public.profiles enable row level security;
alter table public.properties enable row level security;
alter table public.rooms enable row level security;
alter table public.tenants enable row level security;
alter table public.payments enable row level security;
alter table public.sms_queue enable row level security;
alter table public.audit_logs enable row level security;

create policy profiles_read on public.profiles for select using (id = auth.uid() or public.is_superadmin());
create policy profiles_update_self on public.profiles for update using (id = auth.uid()) with check (id = auth.uid());
create policy profiles_superadmin_all on public.profiles for all using (public.is_superadmin()) with check (public.is_superadmin());

create policy properties_owner_read on public.properties for select using (owner_id = auth.uid() or public.is_superadmin());
create policy properties_owner_write on public.properties for all using (owner_id = auth.uid() or public.is_superadmin()) with check (owner_id = auth.uid() or public.is_superadmin());

create policy rooms_owner_access on public.rooms for all using (owner_id = auth.uid() or public.is_superadmin()) with check (owner_id = auth.uid() or public.is_superadmin());
create policy tenants_owner_access on public.tenants for all using (owner_id = auth.uid() or public.is_superadmin()) with check (owner_id = auth.uid() or public.is_superadmin());
create policy payments_owner_access on public.payments for all using (owner_id = auth.uid() or public.is_superadmin()) with check (owner_id = auth.uid() or public.is_superadmin());
create policy sms_owner_access on public.sms_queue for all using (owner_id = auth.uid() or public.is_superadmin()) with check (owner_id = auth.uid() or public.is_superadmin());
create policy audit_superadmin_read on public.audit_logs for select using (public.is_superadmin());

create or replace function public.set_updated_at()
returns trigger language plpgsql as $$ begin new.updated_at = now(); return new; end; $$;

create trigger profiles_updated_at before update on public.profiles for each row execute function public.set_updated_at();
create trigger properties_updated_at before update on public.properties for each row execute function public.set_updated_at();
create trigger rooms_updated_at before update on public.rooms for each row execute function public.set_updated_at();
create trigger tenants_updated_at before update on public.tenants for each row execute function public.set_updated_at();
create trigger payments_updated_at before update on public.payments for each row execute function public.set_updated_at();

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public
as $$ begin
  insert into public.profiles (id, email, display_name, phone)
  values (new.id, new.email, coalesce(new.raw_user_meta_data ->> 'display_name', ''), new.phone)
  on conflict (id) do nothing;
  return new;
end; $$;

create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();
