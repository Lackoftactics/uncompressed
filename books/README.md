# books — Reading Server

Kavita reading server for books, comics, and manga.

## Services

- **kavita** — Multi-format reading server (EPUB, PDF, CBZ, CBR). Web interface with multi-user support and reading progress tracking.

## Media Directories

```
/mnt/user/media/
├── books/    # Main library
├── comics/   # Comics (read-only mount)
└── manga/    # Manga (read-only mount)
```

## Notes

- Independent from the arr stack — no VPN dependency.
- Traefik routes to `kavita.${DOMAIN_NAME}` with security headers (X-Frame-Options, X-Content-Type-Options).
- Health check: `curl http://localhost:5000/health`.
