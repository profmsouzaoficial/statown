-- ============================================================================
-- StaTown - Supabase: contas, progresso por aluno e nota de participacao
-- Execute no SQL Editor do projeto Supabase (uma vez).
--
-- Modelo de confianca:
--   * o cliente usa a anon key (publica);
--   * RLS impede ler/escrever dados de outro aluno;
--   * as RPCs statown_carregar/statown_salvar rodam como SECURITY DEFINER,
--     sempre filtrando por auth.uid();
--   * a nota e uma coluna GERADA no banco: min(100, moedas_ganhas / 10).
--   * o professor e marcado manualmente na tabela statown_alunos.
--
-- Isto NAO torna o jogo a prova de fraude: o cliente ainda envia o save. Para
-- anti-cheat forte seria preciso simular a partida no servidor. A nota e
-- auditavel e as moedas declaradas ficam registradas com data/hora.
-- ============================================================================

-- 1. Perfil do aluno ---------------------------------------------------------
create table if not exists public.statown_alunos (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null default '',
  nome text not null default '',
  matricula text,
  professor boolean not null default false,
  criado_em timestamptz not null default now()
);

create index if not exists statown_alunos_matricula_idx
  on public.statown_alunos (matricula);

-- 2. Progresso por semestre --------------------------------------------------
create table if not exists public.statown_progresso (
  aluno_id uuid not null references public.statown_alunos(id) on delete cascade,
  semestre text not null check (semestre ~ '^[0-9]{4}/[12]$'),
  semana int not null check (semana between 1 and 52),
  ano int not null check (ano between 1 and 999),
  moedas int not null default 0 check (moedas >= 0),
  moedas_ganhas int not null default 0 check (moedas_ganhas >= 0),
  moedas_gastas int not null default 0 check (moedas_gastas >= 0),
  nota int generated always as (least(100, moedas_ganhas / 10)) stored,
  save_data jsonb not null check (jsonb_typeof(save_data) = 'object'),
  atualizado_em timestamptz not null default now(),
  primary key (aluno_id, semestre)
);

create index if not exists statown_progresso_semestre_idx
  on public.statown_progresso (semestre);

-- 3. Perfil criado automaticamente no cadastro -------------------------------
create or replace function public.statown_novo_usuario()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.statown_alunos (id, email, nome, matricula)
  values (
    new.id,
    coalesce(new.email, ''),
    coalesce(new.raw_user_meta_data->>'nome', ''),
    nullif(trim(coalesce(new.raw_user_meta_data->>'matricula', '')), '')
  )
  on conflict (id) do update
    set email = excluded.email,
        nome = case when excluded.nome <> '' then excluded.nome else public.statown_alunos.nome end,
        matricula = coalesce(excluded.matricula, public.statown_alunos.matricula);
  return new;
end;
$$;

drop trigger if exists statown_on_auth_user_created on auth.users;
create trigger statown_on_auth_user_created
  after insert or update of email, raw_user_meta_data on auth.users
  for each row execute function public.statown_novo_usuario();

-- 4. "O usuario logado e professor?" ----------------------------------------
create or replace function public.statown_eh_professor()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((select professor from public.statown_alunos where id = auth.uid()), false);
$$;

revoke all on function public.statown_eh_professor() from public, anon;
grant execute on function public.statown_eh_professor() to authenticated;

-- 5. RLS ---------------------------------------------------------------------
alter table public.statown_alunos enable row level security;
alter table public.statown_progresso enable row level security;

drop policy if exists statown_alunos_select on public.statown_alunos;
create policy statown_alunos_select on public.statown_alunos
  for select to authenticated
  using (id = auth.uid() or public.statown_eh_professor());

drop policy if exists statown_progresso_select on public.statown_progresso;
create policy statown_progresso_select on public.statown_progresso
  for select to authenticated
  using (aluno_id = auth.uid() or public.statown_eh_professor());

-- O cliente nao escreve direto: so pelas RPCs abaixo.
revoke insert, update, delete on public.statown_alunos from anon, authenticated;
revoke insert, update, delete on public.statown_progresso from anon, authenticated;
revoke all on public.statown_alunos from anon;
revoke all on public.statown_progresso from anon;
grant select on public.statown_alunos to authenticated;
grant select on public.statown_progresso to authenticated;

-- 6. Carregar o progresso do aluno logado -----------------------------------
create or replace function public.statown_carregar(p_semestre text)
returns setof public.statown_progresso
language sql
stable
security definer
set search_path = public
as $$
  select *
  from public.statown_progresso
  where aluno_id = auth.uid()
    and semestre = p_semestre;
$$;

revoke all on function public.statown_carregar(text) from public, anon;
grant execute on function public.statown_carregar(text) to authenticated;

-- 7. Salvar o progresso ------------------------------------------------------
-- O cliente manda o save completo; o servidor valida os campos que usa na
-- nota e grava a semana/ano. `nota` e recalculada pela coluna gerada.
create or replace function public.statown_salvar(p_semestre text, p_save jsonb)
returns public.statown_progresso
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_semana int;
  v_ano int;
  v_moedas int;
  v_ganhas int;
  v_gastas int;
  v_row public.statown_progresso;
begin
  if v_uid is null then
    raise exception 'nao autenticado' using errcode = '28000';
  end if;
  if p_semestre !~ '^[0-9]{4}/[12]$' then
    raise exception 'semestre invalido' using errcode = '22023';
  end if;
  if p_save is null or jsonb_typeof(p_save) <> 'object' then
    raise exception 'save invalido' using errcode = '22023';
  end if;
  -- O save tem que pertencer ao semestre da linha. Sem isso, um cliente antigo
  -- poderia empurrar moedas de 2026/1 para a nota de 2026/2.
  if p_save->>'semestre' is distinct from p_semestre then
    raise exception 'save de outro semestre' using errcode = '22023';
  end if;
  if pg_column_size(p_save) > 120000 then
    raise exception 'save grande demais' using errcode = '22023';
  end if;

  begin
    v_semana := coalesce((p_save->>'semana')::int, 1);
    v_ano := coalesce((p_save->>'ano')::int, 1);
    v_moedas := coalesce((p_save->>'moedas')::int, 0);
    v_ganhas := coalesce((p_save->>'moedas_ganhas')::int, 0);
    v_gastas := coalesce((p_save->>'moedas_gastas')::int, 0);
  exception when others then
    raise exception 'campos numericos invalidos no save' using errcode = '22023';
  end;

  if v_semana < 1 or v_semana > 52 or v_ano < 1 or v_ano > 999
     or v_moedas < 0 or v_ganhas < 0 or v_gastas < 0 or v_ganhas > 1000000 then
    raise exception 'progresso fora dos limites' using errcode = '22023';
  end if;

  insert into public.statown_alunos (id, email)
  values (v_uid, coalesce(auth.jwt()->>'email', ''))
  on conflict (id) do nothing;

  insert into public.statown_progresso
    (aluno_id, semestre, semana, ano, moedas, moedas_ganhas, moedas_gastas, save_data)
  values
    (v_uid, p_semestre, v_semana, v_ano, v_moedas, v_ganhas, v_gastas, p_save)
  on conflict (aluno_id, semestre) do update set
    semana = excluded.semana,
    ano = excluded.ano,
    moedas = excluded.moedas,
    moedas_ganhas = excluded.moedas_ganhas,
    moedas_gastas = excluded.moedas_gastas,
    save_data = excluded.save_data,
    atualizado_em = now()
  returning * into v_row;

  return v_row;
end;
$$;

revoke all on function public.statown_salvar(text, jsonb) from public, anon;
grant execute on function public.statown_salvar(text, jsonb) to authenticated;

-- 8. Visao para o professor --------------------------------------------------
-- security_invoker faz a view respeitar a RLS de quem consulta. O professor
-- ve a turma; o aluno ve apenas a propria linha.
create or replace view public.statown_notas
with (security_invoker = true)
as
select
  p.semestre,
  a.nome,
  a.email,
  a.matricula,
  p.semana,
  p.ano,
  p.moedas,
  p.moedas_ganhas,
  p.moedas_gastas,
  p.nota,
  p.atualizado_em
from public.statown_progresso p
join public.statown_alunos a on a.id = p.aluno_id;

grant select on public.statown_notas to authenticated;

-- 9. Como promover um professor (rode uma vez, trocando o e-mail) ------------
-- update public.statown_alunos set professor = true
-- where email = 'professor@instituicao.br';

-- 10. Consulta da turma (professor) -----------------------------------------
-- select * from public.statown_notas
-- where semestre = '2026/2'
-- order by nome;
