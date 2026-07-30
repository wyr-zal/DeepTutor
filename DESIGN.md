# Design

## Source of truth

- Status: Active
- Last refreshed: 2026-07-28
- Primary product surfaces: existing Web workspace and the Android companion app in `mobile/`
- Evidence reviewed: `README.md`, `web/app/globals.css`, `web/lib/theme.ts`, `web/components/ui/Button.tsx`, `web/components/quiz/QuizViewer.tsx`, `web/locales/{en,zh}/app.json`, and runtime assets under `web/public/`

## Brand

- Personality: calm, academic, trustworthy, and helpful; learning content stays ahead of AI decoration.
- Trust signals: transparent progress, explicit network and permission states, readable explanations, and reversible retry paths.
- Avoid: marketing-style gradients, decorative glass effects, emoji as control icons, dense desktop navigation on phones, or color-only correctness cues.

## Product goals

- Goals: help learners complete a short loop of selecting a knowledge base, generating questions, answering by text or voice, and receiving streamed AI feedback.
- Non-goals: mobile knowledge-base administration, provider configuration, generic chat, or feature parity with the desktop workspace.
- Success signals: a learner can complete a quiz without desktop interaction; every long-running step exposes progress and a recovery action.

## Personas and jobs

- Primary personas: existing DeepTutor learners using an Android phone during short study sessions.
- User jobs: reconnect to a deployed DeepTutor instance, choose available material, practice a focused topic, dictate an answer, and revisit recent attempts.
- Key contexts of use: one-handed phone use, intermittent networks, noisy environments, and accessibility text scaling.

## Information architecture

- Primary navigation: two top-level destinations, Practice and History.
- Core routes/screens: bootstrap, login/server setup, knowledge-base home, quiz setup, quiz answer and judgment, history.
- Content hierarchy: current task and recovery action first; configuration and diagnostic detail second.

## Design principles

- One primary action per screen; disable it while the action is running.
- Preserve task state across normal back navigation and make destructive resets explicit.
- Stream useful content immediately; do not hide long work behind a blocking spinner.
- Explain error cause and recovery together, especially for offline, expired session, microphone denial, and unsupported audio.
- Tradeoff: the Android MVP favors a dependable linear practice flow over desktop feature breadth.

## Visual language

- Color: semantic tokens mirror the Web Default/Dark themes. Light uses background `#FFFFFF`, foreground `#0D0D0D`, primary `#2563EB`, muted `#F2F2F2`, border `#E5E5E5`, destructive `#D92D20`. Dark uses background `#1A1918`, foreground `#E8E4DE`, card `#242220`, primary `#D4734B`, muted `#2A2725`, border `#3A3634`.
- Typography: platform sans for controls and body copy; serif is optional for short learning headings. Chinese always keeps a system CJK fallback.
- Spacing/layout rhythm: 4/8dp scale, 16dp phone gutters, wider centered content on tablets.
- Shape/radius/elevation: 8-16dp radii, light borders, low elevation, and cards only for real grouping.
- Motion: native 150-300ms transitions that explain state change; no essential information depends on motion.
- Imagery/iconography: `web/public/logo.png` and `web/public/banner.png` are canonical brand sources. Use one outlined Material icon family; never use emoji as structural icons.

## Components

- Existing components to reuse conceptually: Web button variants, quiz progress, question content, answer editor, judgment and reference-answer sections.
- New/changed components: server-aware login form, knowledge-base selector, quiz setup form, press-and-hold recorder, streaming status, offline banner, and attempt summary.
- Variants and states: default, pressed, focused, loading, disabled, empty, error, success, offline, expired-session, and permission-denied.
- Token/component ownership: Flutter theme owns semantic color and shape tokens; feature widgets do not introduce ad-hoc palettes.

## Accessibility

- Target standard: WCAG 2.2 AA principles plus Android Material accessibility conventions.
- Keyboard/focus behavior: logical traversal on hardware keyboards; the first invalid field receives focus after failed submission.
- Contrast/readability: normal text targets at least 4.5:1; correctness and errors always combine icon, label, and color.
- Screen-reader semantics: all controls expose labels, roles, selected/disabled state, and live progress descriptions.
- Reduced motion and sensory considerations: honor platform reduced-motion settings and support large text without clipping.

## Responsive behavior

- Supported breakpoints/devices: Android phones from 360dp, large phones, tablets, portrait and landscape.
- Layout adaptations: single column on phones; centered readable-width content and optional two-pane summaries on tablets.
- Touch/hover differences: every target is at least 48dp with at least 8dp separation; no hover-only or gesture-only critical action.

## Interaction states

- Loading: inline progress plus a concrete action label.
- Empty: explain why content is absent and where the user can resolve it; mobile does not offer knowledge-base creation.
- Error: show cause, retry, and a sign-in route for 401/WS close code 4001.
- Success: concise confirmation followed by the next learning action.
- Disabled: visibly muted and semantically disabled with a reason when useful.
- Offline/slow network: retain entered answers, stop automatic retries after a bounded attempt, and expose manual reconnect.

## Content voice

- Tone: concise, respectful, instructional, and specific about recovery.
- Terminology: reuse the Web en/zh vocabulary for login, knowledge point, question type, difficulty, judging, and reference answer.
- Microcopy rules: the Android MVP currently ships Simplified Chinese UI copy; STT language is configured independently per attempt; future locale expansion should reuse the Web en/zh vocabulary and never expose raw exceptions when an actionable translation exists.

## Implementation constraints

- Framework/styling system: Flutter, Material 3, Riverpod, and `go_router`; Android only for the MVP.
- Design-token constraints: explicit light/dark `ColorScheme` values; do not use `ColorScheme.fromSeed` to invent a third palette.
- Performance constraints: bounded WebSocket reconnects, cancellation on disposal, incremental streaming, and no unbounded in-memory attempt list.
- Compatibility constraints: HTTPS/WSS in production; cleartext HTTP is permitted only in a debug Android manifest.
- Test/screenshot expectations: model/parser and service tests, widget tests for key states, `flutter analyze`, debug/release APK builds, and phone/tablet visual checks when an emulator or device is available.

## Open questions

- [ ] Confirm the final adaptive launcher-icon crop and background before store distribution; MVP may use the canonical logo on the light primary surface.
- [ ] Add Flutter localization resources before claiming device-locale zh/en UI support.
- [ ] Confirm whether server-backed quiz-attempt grouping should replace local attempt history after the backend exposes a dedicated attempt resource.
