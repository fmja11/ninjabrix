-- =========================================================
-- NINJABRIX MARKETPLACE — DATABASE SCHEMA
-- Designed for Supabase (Postgres + built-in auth.users)
-- Run this in the Supabase SQL editor to set up your backend.
-- =========================================================

-- ---------- PROFILES ----------
-- Extends Supabase's built-in auth.users with marketplace-specific fields.
create table profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null,
  role text not null default 'buyer' check (role in ('buyer','seller','owner')),
  city text,
  created_at timestamptz not null default now()
);

-- ---------- LISTINGS ----------
create table listings (
  id uuid primary key default gen_random_uuid(),
  seller_id uuid not null references profiles(id) on delete cascade,
  title text not null,
  description text,
  category text not null check (category in ('dojo','elemental','rare','bundle','parts')),
  condition text not null check (condition in ('new','used','parts')),
  price numeric(10,2) not null check (price >= 0),
  city text not null,
  status text not null default 'active' check (status in ('pending_review','active','sold','removed')),
  created_at timestamptz not null default now()
);

-- ---------- CONVERSATIONS ----------
create table conversations (
  id uuid primary key default gen_random_uuid(),
  listing_id uuid references listings(id) on delete set null,
  buyer_id uuid not null references profiles(id) on delete cascade,
  seller_id uuid not null references profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (listing_id, buyer_id, seller_id)
);

-- ---------- MESSAGES ----------
create table messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references conversations(id) on delete cascade,
  sender_id uuid not null references profiles(id) on delete cascade,
  body text not null,
  created_at timestamptz not null default now()
);

-- ---------- SALES / COMMISSION LEDGER ----------
create table sales (
  id uuid primary key default gen_random_uuid(),
  listing_id uuid not null references listings(id) on delete restrict,
  buyer_id uuid not null references profiles(id),
  seller_id uuid not null references profiles(id),
  sale_price numeric(10,2) not null check (sale_price >= 0),
  commission_amount numeric(10,2) generated always as (round(sale_price * 0.05, 2)) stored,
  seller_payout numeric(10,2) generated always as (round(sale_price * 0.95, 2)) stored,
  status text not null default 'pending' check (status in ('pending','paid_out','disputed')),
  created_at timestamptz not null default now()
);

-- ---------- INDEXES ----------
create index idx_listings_seller on listings(seller_id);
create index idx_listings_status on listings(status);
create index idx_listings_category on listings(category);
create index idx_messages_conversation on messages(conversation_id);
create index idx_sales_seller on sales(seller_id);

-- =========================================================
-- ROW LEVEL SECURITY
-- This is what actually enforces "Owner-only" access server-side —
-- the front-end check alone is NOT secure on its own.
-- =========================================================

alter table profiles enable row level security;
alter table listings enable row level security;
alter table conversations enable row level security;
alter table messages enable row level security;
alter table sales enable row level security;

-- Profiles: anyone can view basic profiles, only the owner can edit their own
create policy "Profiles are viewable by everyone"
  on profiles for select using (true);
create policy "Users can update their own profile"
  on profiles for update using (auth.uid() = id);

-- Listings: everyone can view active listings; only the seller can edit/delete their own
create policy "Active listings are viewable by everyone"
  on listings for select using (status = 'active' or seller_id = auth.uid());
create policy "Sellers can insert their own listings"
  on listings for insert with check (seller_id = auth.uid());
create policy "Sellers can update their own listings"
  on listings for update using (seller_id = auth.uid());

-- Conversations & messages: only participants can see them
create policy "Participants can view their conversations"
  on conversations for select using (auth.uid() = buyer_id or auth.uid() = seller_id);
create policy "Participants can view their messages"
  on messages for select using (
    exists (select 1 from conversations c where c.id = conversation_id
            and (c.buyer_id = auth.uid() or c.seller_id = auth.uid()))
  );
create policy "Participants can send messages"
  on messages for insert with check (
    sender_id = auth.uid() and
    exists (select 1 from conversations c where c.id = conversation_id
            and (c.buyer_id = auth.uid() or c.seller_id = auth.uid()))
  );

-- Sales: buyer, seller, and owners can view; only Owners can view the full ledger
create policy "Buyers and sellers can view their own sales"
  on sales for select using (auth.uid() = buyer_id or auth.uid() = seller_id);
create policy "Owners can view all sales"
  on sales for select using (
    exists (select 1 from profiles p where p.id = auth.uid() and p.role = 'owner')
  );

-- =========================================================
-- NOTES
-- 1. The `role` column drives Owner-dashboard access. Set it to 'owner'
--    manually for your own account after signing up (via the Supabase
--    table editor) — never let users self-assign 'owner' from the app.
-- 2. commission_amount and seller_payout are computed automatically —
--    you never need to calculate 5% by hand.
-- 3. Actually moving money still requires a payment processor
--    (Moyasar, HyperPay, Tap, or PayTabs for SAR/mada support) —
--    this schema tracks who owes what, it doesn't move funds itself.
-- =========================================================
