## Unreleased

## v1.4.0 (2022-04-27)

### Feat

- **logging**: configure OpenTelemetry

## v1.3.0 (2022-04-26)

### Feat

- **logging**: add configuration by LOG_LEVEL env var

## v1.2.1 (2022-02-24)

### Refactor

- central build ci ([#11](https://github.com/PlaceOS/dispatch/pull/11))

## v1.2.0 (2021-10-11)

### Refactor

- change base endpoint `/server/` -> `/dispatch/v1/`
- `/server/` -> `/dispatch/v1/`

### Feat

- conform to PlaceOS::Model::Version
- conform to PlaceOS::Model::Version
- **logging**: add placeos log backend
- add /api/server/healthz route
- add secrets and cleanup ENV
- update to crystal 0.34
- add support for crystal 0.34
- **Dockerfile**: build images using alpine
- **Docker**: build minimal image
- fix issues with binary streams

### Fix

- add PLACE_VERSION
- reading data out of buffer
- dev builds
- **LICENSE**: correct copyright holder reference
- **Dockerfile**: remove from scratch
- **specs**: ensure client has closed
- issues identified by ameba
