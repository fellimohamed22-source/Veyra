create table if not exists client_favorite_drivers (
  client_user_id uuid not null references users(id) on delete cascade,
  driver_id uuid not null references drivers(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (client_user_id, driver_id)
);
create index if not exists idx_client_favorite_drivers_driver on client_favorite_drivers(driver_id);
