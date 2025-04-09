# Makefile
#
# Use this Makefile to set up a local Docker PostgreSQL database and run tests, or launch a local
# development database.
#
## Tests
#
# Set up test database and run application tests:
#
# ```
# make test
# ```
#
## Development
#
# Set up development database and launch the demo Jetzig app:
#
# ```
# make dev
# ```
#
# TODO: Move all of this into `build.zig`
test_database=jetzig_demo_test
dev_database=jetzig_demo_dev
port=14173

export JETQUERY_HOSTNAME=localhost
export JETQUERY_USERNAME=postgres
export JETQUERY_PASSWORD=postgres
export JETQUERY_POOL_SIZE=2

.PHONY: test
test: env=JETQUERY_DATABASE=${test_database} JETQUERY_PORT=${port}
test:
	docker compose up --detach --wait --renew-anon-volumes --remove-orphans --force-recreate
	${env} zig build -Denvironment=testing jetzig:database:setup
	${env} zig build -Denvironment=testing jetzig:test

.PHONY: dev
dev: env=JETQUERY_DATABASE=${dev_database} JETQUERY_PORT=${port}
dev:
	docker compose up --detach --wait --renew-anon-volumes --remove-orphans
	${env} zig build -Denvironment=testing jetzig:database:setup
	${env} jetzig server
