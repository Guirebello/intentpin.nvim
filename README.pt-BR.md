# IntentPin.nvim

[English](README.md)

Transforme seleções exatas de código em contexto persistente e editável para assistentes de programação com IA.

O IntentPin permite selecionar um trecho, anexar uma nota ou pergunta e manter essa intenção conectada ao código enquanto o arquivo muda. Revise tudo dentro do Neovim, escolha o que entra no próximo pedido e copie um prompt compacto para Codex, Claude Code, ChatGPT, Copilot ou qualquer outro assistente baseado em texto.

## Demonstração

https://github.com/user-attachments/assets/5c136e66-1941-4c97-8d8c-5eaf7464e4a2

> [!NOTE]
> O IntentPin.nvim é experimental. As notas ficam no diretório de estado do Neovim, e o formato usado para armazená-las pode mudar antes da versão 1.0.
>
> O plugin inclui dois renderizadores de hover. `virtual_lines` é o padrão e nunca cobre o código; `floating_window` oferece uma janela compacta.

## Por que IntentPin?

Ferramentas de IA funcionam melhor com contexto preciso, mas reunir caminhos, intervalos de linhas, trechos de código e instruções separadas interrompe o fluxo de edição. O IntentPin transforma esse contexto em notas persistentes criadas diretamente a partir de seleções visuais, sem gravar metadados no projeto.

## Recursos

- Anexe notas e perguntas multilinha a intervalos exatos de caracteres.
- Acompanhe edições com extmarks e reencontre código movido usando o texto selecionado e seu contexto.
- Identifique âncoras perdidas por avisos consistentes no gutter, manager e preview.
- Leia uma nota usando virtual lines temporárias ou uma floating window.
- Expanda todas as notas do arquivo atual sem cobrir o código.
- Revise, edite, inclua, exclua, apague, navegue e exporte notas pelo manager flutuante.
- Exporte caminhos relativos ou absolutos com instruções em inglês, português, espanhol ou personalizadas.
- Mantenha todos os dados do IntentPin fora do repositório do projeto.

## Requisitos

- Neovim 0.11.2 ou mais recente
- [nui.nvim](https://github.com/MunifTanjim/nui.nvim), instalado automaticamente pela configuração fornecida para lazy.nvim
- Um clipboard provider é opcional; sem ele, os exports ainda são escritos no registro sem nome do Neovim

Nenhuma dependência adicional de runtime precisa ser instalada manualmente ao usar a configuração fornecida para lazy.nvim ou LazyVim.

## Instalação

Com lazy.nvim ou LazyVim, crie `lua/plugins/intentpin.lua`:

```lua
return {
  {
    "Guirebello/intentpin.nvim",
    dependencies = {
      "MunifTanjim/nui.nvim",
    },
    event = { "BufReadPost", "BufNewFile" },
    cmd = "IntentPin",
    opts = {
      hover = {
        mode = "virtual_lines", -- ou "floating_window"
      },
      editor = {
        spell = false,
        diagnostics = false,
        completion = false,
      },
      export = {
        instruction_language = "pt-BR",
      },
    },
    keys = {
      { "<leader>ia", "<cmd>IntentPin add<cr>", mode = "x", desc = "Add IntentPin" },
      { "<leader>ii", "<cmd>IntentPin open<cr>", desc = "IntentPin Notes" },
      { "<leader>ih", "<cmd>IntentPin hover<cr>", desc = "Hover IntentPin" },
      { "<leader>iH", "<cmd>IntentPin expand<cr>", desc = "Expand IntentPins in File" },
      { "<leader>is", "<cmd>IntentPin show<cr>", desc = "Show IntentPin at Cursor" },
      { "<leader>ie", "<cmd>IntentPin edit<cr>", desc = "Edit IntentPin at Cursor" },
      { "<leader>iy", "<cmd>IntentPin copy checked<cr>", desc = "Copy Checked IntentPins" },
      { "<leader>iY", "<cmd>IntentPin copy all-absolute<cr>", desc = "Copy All IntentPins (Absolute Paths)" },
      { "]i", "<cmd>IntentPin next<cr>", desc = "Next IntentPin" },
      { "[i", "<cmd>IntentPin prev<cr>", desc = "Previous IntentPin" },
    },
  },
}
```

Para desenvolvimento local, substitua a string do repositório por:

```lua
dir = "/caminho/para/intentpin.nvim",
name = "intentpin.nvim",
```

## Fluxo de uso

1. Selecione um trecho de código no modo visual.
2. Execute `:IntentPin add` e escreva uma nota ou pergunta multilinha.
3. Salve com `<C-s>`.
4. Abra `:IntentPin open` para revisar, incluir, editar, apagar, navegar e exportar notas.

No editor de notas, `<Esc>` e `<C-c>` apenas retornam ao modo Normal. Feche explicitamente com `q` ou `:q`.

O spellcheck vem desativado. Use `editor.spell = true` e, opcionalmente, configure `editor.spelllang`. Com o editor aberto, comandos nativos como `]s`, `[s` e `z=` continuam disponíveis.

Diagnósticos Markdown também vêm desativados, impedindo que markdownlint ou um LSP trate uma nota curta como um documento completo. Use `editor.diagnostics = true` para ativá-los.

O autocomplete também vem desativado no editor de notas, incluindo o autocomplete nativo do Neovim, `nvim-cmp` e `blink.cmp`. Use `editor.completion = true` para preservar o comportamento dos seus buffers normais.

Por padrão, o intervalo selecionado recebe apenas um símbolo no gutter. `:IntentPin hover` destaca temporariamente o trecho exato e mostra o comentário com o renderizador configurado. O comentário fecha ao mover o cursor, entrar em Insert ou repetir o comando.

`:IntentPin expand` alterna todas as notas do arquivo atual como virtual lines persistentes. Elas continuam abertas durante navegação e edição; execute novamente para recolher. `:IntentPin expand show` e `:IntentPin expand hide` oferecem controle explícito.

Seleções visuais em bloco ainda são rejeitadas porque um retângulo não pode ser representado com segurança por um único intervalo.

## Comandos

```text
:IntentPin add
:IntentPin open
:IntentPin show
:IntentPin edit
:IntentPin delete
:IntentPin hover
:IntentPin expand
:IntentPin expand show
:IntentPin expand hide
:IntentPin reanchor
:IntentPin inline show
:IntentPin inline hide
:IntentPin inline toggle
:IntentPin next
:IntentPin prev
:IntentPin clear
:IntentPin copy checked
:IntentPin copy checked-absolute
:IntentPin copy all
:IntentPin copy all-absolute
:IntentPin copy current
:IntentPin copy current-absolute
```

`show`, `edit`, `delete` e `copy current` operam sobre a nota sob o cursor. Quando intervalos se sobrepõem, o IntentPin permite escolher a nota.

`copy all-absolute` ignora as checkboxes, copia todas as notas do projeto e usa caminhos completos. Todo comando de cópia inclui a instrução configurada em `export`.

## Modos de hover

Os dois modos destacam temporariamente os caracteres selecionados com `IntentPinActiveRange` e deixam `K` livre para o hover do LSP.

- `virtual_lines` renderiza um card após o intervalo. Desloca as linhas da tela sem modificar o arquivo nem cobrir o código.
- `floating_window` renderiza uma janela compacta próxima ao cursor. Ocupa menos espaço vertical, mas pode cobrir parte do editor.

Escolha com `hover.mode` e use `<leader>ih` ou `:IntentPin hover` com o cursor dentro de um intervalo fixado. O modo que expande todo o arquivo sempre usa virtual lines, independentemente de `hover.mode`.

## Manager flutuante

| Tecla | Ação |
| --- | --- |
| `<CR>` | Ir para o código da nota |
| `<Space>` | Incluir ou excluir a nota dos exports marcados |
| `a` | Incluir todas as notas |
| `u` | Excluir todas as notas |
| `e` | Editar a nota |
| `d` | Apagar a nota |
| `D` | Apagar todas as notas do projeto |
| `y` | Copiar a nota atual |
| `Y` | Copiar notas marcadas com caminhos relativos |
| `gY` | Copiar notas marcadas com caminhos absolutos |
| `A` | Copiar todas as notas com caminhos relativos |
| `p` | Alternar o preview |
| `r` | Tentar recuperar âncoras em arquivos carregados e mostrar o resultado |
| `?` | Abrir o buffer persistente de ajuda |
| `q` / `<Esc>` | Fechar |

Em telas largas, lista e preview aparecem lado a lado; em telas estreitas, ficam empilhados. A ajuda permanece aberta até `?`, `q` ou `<Esc>`.

## Configuração

```lua
require("intentpin").setup({
  root_markers = { ".git" },
  -- root_dir = function(path) return ... end,
  context_lines = 2,
  inline = {
    enabled = true,
    sign = "󰆉",
    orphan_sign = "!",
    virtual_text = false,
    max_length = 60,
    highlight_range = false,
    priority = 120,
  },
  hover = {
    mode = "virtual_lines", -- virtual_lines ou floating_window
    width = 72,
    max_height = 14, -- somente floating_window
    -- Estilos nativos do NUI: default, double, none, rounded, shadow, single ou solid.
    -- none e shadow não exibem títulos na borda.
    border = "rounded", -- somente floating_window
  },
  editor = {
    width = 0.62,
    height = 0.32,
    -- Estilos nativos do NUI: default, double, none, rounded, shadow, single ou solid.
    -- none e shadow ocultam o título e as dicas de atalhos exibidos na borda.
    border = "rounded",
    spell = false,
    spelllang = nil, -- exemplo: "pt_br,en_us"
    diagnostics = false,
    completion = false, -- completion nativo, nvim-cmp e blink.cmp
  },
  manager = {
    width = 0.88,
    height = 0.76,
    -- Estilos nativos do NUI: default, double, none, rounded, shadow, single ou solid.
    -- none e shadow ocultam os títulos e as dicas de atalhos exibidos nas bordas.
    border = "rounded",
    preview = true,
  },
  export = {
    include_selected_text = true,
    instruction_language = "pt-BR", -- en, pt-BR, es ou custom
    custom_instruction = "",
  },
})
```

Todos os grupos de highlight começam com `IntentPin` e podem ser sobrescritos pelo colorscheme ou configuração do usuário.

## Armazenamento e reancoragem

O IntentPin nunca cria metadados dentro do projeto. O estado é salvo em:

```text
stdpath("state")/intentpin/<sha256-da-raiz-do-projeto>.json
```

As gravações usam um arquivo temporário seguido de uma substituição atômica. Enquanto o buffer está carregado, extmarks acompanham as edições. Ao reabrir um arquivo, o IntentPin testa o intervalo salvo e depois procura o texto original, classificando resultados por contexto e distância. Quando não encontra o trecho, preserva a nota e mostra um aviso em vez de descartá-la.

Execute `:checkhealth intentpin` para verificar Neovim, NUI, storage e clipboard.

## Formato exportado

```text
Faça as alterações indicadas e responda às perguntas. Altere código somente quando necessário para atender a um pedido de mudança.

src/auth/login.ts:14-15
| const session = await getSession(token)
| return session ?? null
> Retorne um erro específico quando o token estiver expirado.
```

## Desenvolvimento

Execute a suíte headless:

```bash
make test
```

## Licença

Licenciado sob Apache License 2.0. Consulte [LICENSE](LICENSE) e [NOTICE](NOTICE).
