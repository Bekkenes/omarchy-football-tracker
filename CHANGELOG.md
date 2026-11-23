# Changelog

## 2026-11-23

### Fixed
- A network error (curl `000`) or an HTTP 4xx/5xx from the API was treated as success, so an empty fixture list was cached for the day and no match notifications were sent. `ft_api` now fails on anything but HTTP 200 (retrying network errors), and `poll.sh` treats API errors in the response (e.g. exhausted quota) as a failed day.
