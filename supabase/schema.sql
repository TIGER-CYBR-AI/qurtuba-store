-- Qurtuba starter schema. Run once in Supabase SQL Editor.
create extension if not exists pgcrypto;

create table if not exists public.admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table if not exists public.categories (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  image_url text,
  is_visible boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  category_id uuid references public.categories(id) on delete set null,
  name text not null,
  description text not null default '',
  specifications text not null default '',
  price numeric(12,2) not null default 0 check (price >= 0),
  unit text not null default 'قطعة',
  quantity integer not null default 0 check (quantity >= 0),
  image_url text,
  is_available boolean not null default true,
  is_visible boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.orders (
  id uuid primary key default gen_random_uuid(),
  order_code text not null unique,
  customer_name text not null,
  customer_phone text not null,
  product_id uuid references public.products(id) on delete set null,
  product_name text not null,
  quantity integer not null check (quantity > 0),
  unit_price numeric(12,2) not null default 0,
  status text not null default 'pending'
    check (status in ('pending','preparing','ready','completed','cancelled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.admins enable row level security;
alter table public.categories enable row level security;
alter table public.products enable row level security;
alter table public.orders enable row level security;

create or replace function public.is_store_admin()
returns boolean language sql stable security definer
set search_path = public
as $$
  select exists(select 1 from public.admins where user_id = auth.uid());
$$;

-- Public can view visible categories/products.
drop policy if exists "public read visible categories" on public.categories;
create policy "public read visible categories" on public.categories
for select using (is_visible or public.is_store_admin());

drop policy if exists "admins manage categories" on public.categories;
create policy "admins manage categories" on public.categories
for all using (public.is_store_admin()) with check (public.is_store_admin());

drop policy if exists "public read visible products" on public.products;
create policy "public read visible products" on public.products
for select using (is_visible or public.is_store_admin());

drop policy if exists "admins manage products" on public.products;
create policy "admins manage products" on public.products
for all using (public.is_store_admin()) with check (public.is_store_admin());

-- Visitors can create a reservation, but can never read customer/order records.
drop policy if exists "public create orders" on public.orders;
create policy "public create orders" on public.orders
for insert with check (
  length(trim(customer_name)) between 2 and 100
  and length(trim(customer_phone)) between 5 and 30
  and quantity > 0
);

drop policy if exists "admins read orders" on public.orders;
create policy "admins read orders" on public.orders
for select using (public.is_store_admin());

drop policy if exists "admins update orders" on public.orders;
create policy "admins update orders" on public.orders
for update using (public.is_store_admin()) with check (public.is_store_admin());

-- Only admins can see their admin membership row.
drop policy if exists "admins read own membership" on public.admins;
create policy "admins read own membership" on public.admins
for select using (user_id = auth.uid());

-- Storage bucket should be created as PUBLIC named product-images in the dashboard.
-- Upload/delete is limited to authenticated store admins.
insert into storage.buckets (id, name, public)
values ('product-images', 'product-images', true)
on conflict (id) do update set public = true;

drop policy if exists "public view product images" on storage.objects;
create policy "public view product images" on storage.objects
for select using (bucket_id = 'product-images');

drop policy if exists "admins upload product images" on storage.objects;
create policy "admins upload product images" on storage.objects
for insert to authenticated
with check (bucket_id = 'product-images' and public.is_store_admin());

drop policy if exists "admins update product images" on storage.objects;
create policy "admins update product images" on storage.objects
for update to authenticated
using (bucket_id = 'product-images' and public.is_store_admin())
with check (bucket_id = 'product-images' and public.is_store_admin());

drop policy if exists "admins delete product images" on storage.objects;
create policy "admins delete product images" on storage.objects
for delete to authenticated
using (bucket_id = 'product-images' and public.is_store_admin());
