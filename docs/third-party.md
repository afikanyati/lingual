# Third-party components

The web app uses the following components under their upstream licenses. Installed packages retain their license files under `web/node_modules`; the lockfile pins versions.

| Component | Use | License/source |
| --- | --- | --- |
| Vosk small-en-us-0.15 | Streaming English speech model | Apache-2.0; [official models](https://alphacephei.com/vosk/models) |
| @lichess-org/vosk-browser 0.0.3 | Vosk WASM worker | Apache-2.0; [source](https://github.com/lichess-org/vosk-browser) |
| Transformers.js 3.8.1 | Browser inference pipeline | Apache-2.0; [project](https://github.com/huggingface/transformers.js), [browser documentation](https://huggingface.co/docs/transformers.js/v3.8.1/index) |
| Xenova/whisper-tiny.en | Downloaded quantized ONNX English speech model | Model card declares Apache-2.0; [model card](https://huggingface.co/Xenova/whisper-tiny.en) |
| OpenAI Whisper | Upstream model architecture/weights | MIT; [source and license](https://github.com/openai/whisper) |
| ONNX Runtime Web | Local WebAssembly inference | MIT; transitive Transformers.js dependency |
| React / React DOM | UI | MIT |
| Vite, TypeScript, Vitest, Playwright, Prettier | Build and test tools | Upstream package licenses (MIT or Apache-2.0) |
| Compromise 14.16.0 | Local English part-of-speech tagging | MIT; [source](https://github.com/spencermountain/compromise) |
| idb | IndexedDB wrapper | ISC |
| Lucide | Interface icons | ISC |

The original Lingual earcons were copied from `diction-processor/sounds/`; their ownership was not changed. Native Beethoven sources and any embedded license notices were retained. No new license was imposed on the user's application source.

The build vendors integrity-checked model files from revision `79fb389fc764e7c395bd330e9531d9d32ada7049` of the public model repository. Visitors load those files and the matching runtime from the static site itself. The generated distribution includes the original model card, Apache-2.0 text, upstream Whisper MIT license and ONNX Runtime MIT license. License sources are retained under `docs/licenses`; the Apache text is copied from the installed Transformers.js package.
