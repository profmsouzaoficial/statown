# Template web da Godot 4.7.2

`web_nothreads_release.zip` foi extraído de
`Godot_v4.7.2-stable_export_templates.tpz`, do release oficial da Godot Engine.
O arquivo é necessário para o export web sem threads usado pelo StaTown.

- Versão: `4.7.2.stable`
- Licença da Godot Engine: MIT
  (<https://godotengine.org/license>)
- Origem: <https://github.com/godotengine/godot/releases/tag/4.7.2-stable>

O `version.txt` permite que a Godot reconheça o diretório de templates. O CI copia
estes dois arquivos para `~/.local/share/godot/export_templates/4.7.2.stable/`.

Não substitua por um template de outra versão: o export precisa casar com o binário
`Godot_v4.7.2-stable_linux.x86_64` baixado pelo workflow.
