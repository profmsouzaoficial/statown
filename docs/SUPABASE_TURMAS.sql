-- ============================================================================
-- StaTown - migration: turma e periodo do SIGA no perfil do aluno
--
-- Rode UMA vez em um projeto que ja tenha o docs/SUPABASE.sql aplicado.
-- Em projeto novo, use o docs/SUPABASE.sql atualizado; ele ja cria as colunas.
--
-- O nome do arquivo de lista do SIGA, por exemplo
--   CBV018GV_A_2026_3.csv
-- vira:
--   turma        = 'CBV018GV-A'
--   periodo_siga = '2026/3'
--
-- `turma` e o mesmo valor que a API AUTO-SIGA espera em "turma":
--   POST /api/lancar-notas
--   {"turma":"CBV018GV-A", "periodo":"2026/3", ...}
--
-- As duas colunas ficam em statown_alunos, mas nao sao editaveis pelo aluno:
-- a RLS ja revoga insert/update direto e o cliente so as recebe no perfil.
-- ============================================================================

begin;

alter table public.statown_alunos
  add column if not exists turma text not null default '';

alter table public.statown_alunos
  add column if not exists periodo_siga text not null default '';

create index if not exists statown_alunos_turma_idx
  on public.statown_alunos (turma, periodo_siga);

comment on column public.statown_alunos.turma is
  'Codigo da turma no SIGA, sem periodo (ex.: CBV018GV-A).';
comment on column public.statown_alunos.periodo_siga is
  'Periodo letivo do SIGA (ex.: 2026/3), separado do semestre interno do jogo.';

-- O trigger e o mesmo do cadastro: passa a copiar turma/periodo do metadata
-- criado pelo Admin API. Se o metadata nao trouxer o campo, preserva o valor
-- que ja existe no perfil.
create or replace function public.statown_novo_usuario()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.statown_alunos
    (id, email, nome, matricula, turma, periodo_siga)
  values (
    new.id,
    coalesce(new.email, ''),
    coalesce(new.raw_user_meta_data->>'nome', ''),
    nullif(trim(coalesce(new.raw_user_meta_data->>'matricula', '')), ''),
    coalesce(new.raw_user_meta_data->>'turma', ''),
    coalesce(new.raw_user_meta_data->>'periodo_siga', '')
  )
  on conflict (id) do update
    set email = excluded.email,
        nome = case when excluded.nome <> '' then excluded.nome else public.statown_alunos.nome end,
        matricula = coalesce(excluded.matricula, public.statown_alunos.matricula),
        turma = case when excluded.turma <> '' then excluded.turma else public.statown_alunos.turma end,
        periodo_siga = case when excluded.periodo_siga <> ''
          then excluded.periodo_siga else public.statown_alunos.periodo_siga end;
  return new;
end;
$$;

-- A view e recriada porque adicionar coluna no meio de uma view existente
-- nao e permitido por CREATE OR REPLACE VIEW.
drop view if exists public.statown_notas;

create view public.statown_notas
with (security_invoker = true)
as
select
  p.semestre,
  a.turma,
  a.periodo_siga,
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
grant select on public.statown_notas to service_role;
grant select, insert, update, delete on public.statown_alunos to service_role;
grant select on public.statown_progresso to service_role;

commit;

-- Faz o PostgREST enxergar as colunas novas imediatamente.
notify pgrst, 'reload schema';
