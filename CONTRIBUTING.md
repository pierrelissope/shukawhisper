# Contributing

Thanks for your interest in ShukaWhisper! Bug reports, ideas and pull requests are welcome.

## Getting started

```bash
xcode-select --install   # if you don't have Xcode or the Command Line Tools
make cert                # once: local signing certificate so permissions survive rebuilds
make test                # unit tests
make run                 # build the .app and launch it
```

Read [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) first. It explains how a dictation flows through the code.

## Guidelines

- **Keep logic in `ShukaCore`** whenever it doesn't need AppKit or the network, and add tests for it.
- **Prompts live in `PromptBuilder`** and nowhere else. If you change one, try it on French, English and mixed samples with `ShukaWhisper --transcribe`.
- **No third-party dependencies** without a strong reason.
- Match the surrounding style: small types, doc comments on anything non-obvious, Swift 6 strict concurrency with no warnings.
- UI changes: run `ShukaWhisper --snapshots out/` and attach the before/after images to your PR.
- Keep PRs focused. One feature or fix per PR is easier to review.

## Reporting bugs

Please include your macOS version, the app or website you were dictating into, what you said (or the kind of speech), and what you expected versus what happened. If it's a latency issue, include the timings from the History screen.
