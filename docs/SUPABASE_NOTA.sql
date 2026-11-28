-- ============================================================================
-- StaTown - migration: nota proporcional 1000 moedas -> nota maxima
--
-- Regra: a avaliacao "Game Educativo Statown" vale 40,0 pontos. A nota e
-- proporcional as moedas GANHAS no semestre:
--   nota = min(40.0, floor(moedas_ganhas / 1000 * 40.0 * 10) / 10)
--
-- O truncamento em uma casa decimal evita que 999 moedas virem 40,0 por
-- arredondamento. O teto de 40,0 continua valendo para qualquer saldo acima
-- de 1000 moedas.
--
-- Rode UMA vez em um projeto que ja tenha o docs/SUPABASE.sql aplicado.
-- A coluna e derivada: recria-la nao perde progresso, apenas recalcula a nota.
-- ============================================================================

begin;

-- A view depende da coluna; remova-a antes de recriar a coluna derivada.
drop view if exists public.statown_notas;

alter table public.statown_progresso
  drop column if exists nota;

alter table public.statown_progresso
  add column nota numeric(4,1) generated always as (
    least(40.0, floor((moedas_ganhas::numeric / 1000.0) * 40.0 * 10.0) / 10.0)
  ) stored;

comment on column public.statown_progresso.nota is
  'Nota de participacao 0..40: 1000 moedas ganhas = 40,0; truncada em 1 casa.';

-- A view precisa ser recriada para o PostgREST enxergar o novo tipo.
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

notify pgrst, 'reload schema';
