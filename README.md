# Fala

Teclado de iPhone para uso pessoal, com ditado 100% local em português do Brasil.

- **Base:** o app de iPhone do [Hex](https://github.com/anomalyco/hex) (licença MIT), importado de `anomalyco/hex` no commit `0304eb1`. Vem dele o teclado, o retorno tátil, a autocorreção e o ditado no próprio iPhone.
- **Por cima:** a barra superior no estilo do Function Keyboard. Ela tem o botão de raio com Reescrever, Formalizar, Traduzir, Contatos e Ajustes, os atalhos que aparecem depois de ditar, as pílulas Reescrevendo e Desfazer, e a gravação com ✕, a onda sonora e o ✓ azul.

Não é distribuído na App Store nem no TestFlight. Ele é instalado direto pelo Xcode.

## Como rodar no iPhone

Você precisa de um Mac com **Xcode 26 ou mais novo** e do [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
cd ios
scripts/fetch-cleanup-model.sh   # baixa o modelo de limpeza do ditado (25 MB, conferido por SHA-256)
xcodegen generate                # gera o HEXMobile.xcodeproj
open HEXMobile.xcodeproj
```

No Xcode:

1. Em **Settings › Accounts**, entre com o seu Apple ID.
2. Selecione o seu time em **Signing & Capabilities** nos alvos `HEXMobile`, `HEXKeyboard` e `HEXWidgets`. Se preferir, coloque o Team ID em `DEVELOPMENT_TEAM` no `ios/project.yml` e rode `xcodegen generate` de novo.
3. Conecte o iPhone, escolha-o como destino e aperte **Run** (⌘R).
4. No iPhone, ative o teclado em **Ajustes › Geral › Teclado › Teclados › Adicionar Novo Teclado › Fala Teclado** e ligue o **Acesso Total**. Ele é necessário para o ditado.

Com um Apple ID gratuito, o app expira em 7 dias. Para não ter que reinstalar, use a conta de desenvolvedor paga ou o SideStore.

## O que mudou em relação ao Hex

| O quê | Hex | Fala |
|---|---|---|
| Prefixo dos identificadores | `anomaly.hex` | `com.simsousantos.fala` |
| App Group (ponte app ↔ teclado) | `group.anomaly.hex.mobile` | `group.com.simsousantos.fala.mobile` |
| Esquema de URL | `hex-dictation://` | `fala-dictation://` |
| Nomes na tela | Hex / Hex Keyboard | Fala / Fala Teclado |
| Time de assinatura | da Anomaly | vazio: você escolhe o seu |

O esquema de URL foi trocado para não conflitar com o Hex oficial instalado no mesmo iPhone.

## Mapa do código (onde mexer)

- `ios/HEXKeyboard/`: a extensão de teclado (controlador, ditado dentro do teclado, Parakeet).
- `ios/HEXShared/FullKeyboard/View/`: a interface do teclado completo. É aqui que entra a barra do Function.
- `ios/HEXShared/FullKeyboard/Engine/` e `Autocorrect/`: o motor de digitação e a autocorreção.
- `ios/HEXMobile/`: o app principal (ajustes, onboarding, gravação fora do teclado).

## Deslizar entre as letras em português

O Hex só desliza em inglês e espanhol (e, em modo experimental, francês, polonês e alemão), porque cada idioma precisa de um modelo de digitação (`.hextm`) feito com o Google Books, que não tem português. O Fala traz o seu próprio `ios/HEXKeyboard/TypingModel/pt.hextm`, gerado por `ios/scripts/build-pt-typing-model.py` a partir de legendas brasileiras (OpenSubtitles 2018, via OPUS) e notícias (Leipzig Corpora Collection, `por_news_2020_1M`, CC BY), com as palavras conferidas no dicionário pt_BR do LibreOffice (VERO). O mesmo modelo lê os toques na autocorreção (como o Hex faz em inglês e espanhol); o dicionário do iOS continua dizendo se uma palavra existe.

## Limpeza do ditado em português

Com "Clean up what I say" ligado (padrão), o ditado em português perde as hesitações ("éé", "ahn", "hum", "hmm") e os vícios entre vírgulas ("Eu, tipo, fui" → "Eu fui"; "tipo", "né", "sabe", "assim"), e uma correção falada fica só com a versão certa ("às 3, digo, às 4" → "às 4"; também "quer dizer", "não", "ou melhor"). São regras de palavras, como as do Hex para espanhol (`SpokenCleanupRules.portuguese`): "amanhã, né?" e "esse tipo de coisa" ficam como foram ditos.

## Português e inglês ao mesmo tempo

Escolha **Português** e **Inglês** em Ajustes › Teclado › Idiomas no app Fala. Como no teclado do iPhone, os dois viram um teclado bilíngue só, sem trocar de idioma: as teclas e os acentos são os do português, a barra de espaço mostra "EN PT" no canto, a autocorreção aceita palavras dos dois e o deslizar lê com os dois modelos (`pt.hextm` e `en.hextm`), com o inglês 1 nat mais caro para uma palavra que existe nos dois idiomas sair em português.

## Licença

O código original é do Hex, © 2026 Christopher Langton, sob licença MIT (ver `LICENSE`). As licenças de terceiros estão em `THIRD_PARTY_NOTICES.md`.
