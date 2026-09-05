# `spec/access.md` — how to fetch a file

Every emission lives in more than one place, served by operators that are not us. Pick whichever
answers fastest from where you are.

> 🇪🇸 En espanol: [`access.es.md`](access.es.md)

## The routes

| Where the file lives | Served by |
|---|---|
| GitHub | **jsDelivr** · **Statically** |
| GitLab | **Statically** |
| This project's site | itself |

jsDelivr does not serve GitLab. That is not a defect of either: it is one route fewer, and the
point is that there are several.

## The URLs

```
https://cdn.jsdelivr.net/gh/<owner>/<repo>@main/<path>
https://cdn.statically.io/gh/<owner>/<repo>@main/<path>
https://cdn.statically.io/gl/<owner>/<repo>@main/<path>
```

`<path>` is the file inside the repository, for example:

```
emissions/2026/08/29/2110-emission.jws
```

## They all serve the same bytes

Checked, not assumed: the same file fetched through each route gives the **same SHA-256**. A CDN in
front of a repository is a cache, not a copy someone maintains.

That matters because of **R6**: the file travels as binary and is not touched. If a route ever
returns different bytes, the signature will not verify — and that is the answer, not a bug in your
code.

## Which one to use

Whichever is closest to you. A CDN routes by proximity, so the fastest one from one continent is
not the fastest from another. Measure from where your users are, not from where we measured.

If you fetch a lot, use a CDN. It is what they are for, and it leaves the repositories alone.

## About this project's own site

It serves the same files, and it is a convenience — not evidence. It is ours: a copy we control
cannot be the proof that we did not change anything. The routes above are the ones that do not
depend on us, and those are the ones to point at when it matters.
