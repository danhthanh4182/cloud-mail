# Third-party licenses note

## Vendored frontend assets

`mail-vue/public/tinymce` is a vendored copy of TinyMCE 7.9.1, which is
licensed **GPL-2.0-or-later**. The same bundle includes DOMPurify
3.2.4, dual-licensed **Apache-2.0 / MPL-2.0**.

These files are served as-is and are intentionally excluded from the
dependency license gates: they are not npm dependencies and cannot be
patched via the package manager. If the GPL terms are a problem for a
deployment, replace the vendored editor (see `docs/backlog.md`).

## Dependency license gates

CI asserts that `pnpm licenses list --prod` reports no AGPL/GPL package
names (LGPL counts as GPL for this check) in `mail-worker` or `mail-vue`.
