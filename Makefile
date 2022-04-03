DOCKER_COMPOSE_EXEC_OPTIONS := $(DOCKER_COMPOSE_EXEC_OPTIONS)

openresty-dev:
	docker-compose up -d openresty
	docker-compose exec $(DOCKER_COMPOSE_EXEC_OPTIONS) -- openresty bash -c 'cd /opt/opentelemetry-lua && luarocks make && nginx -s reload'

openresty-test-e2e:
	docker-compose run -e PROXY_ENDPOINT=http://openresty/test/e2e --use-aliases --rm test-client

openresty-test-e2e-trace-context:
	docker-compose exec $(DOCKER_COMPOSE_EXEC_OPTIONS) -- openresty bash /opt/opentelemetry-lua/e2e-trace-context.sh

openresty-unit-test:
	docker-compose exec $(DOCKER_COMPOSE_EXEC_OPTIONS) -- openresty bash -c 'cd /opt/opentelemetry-lua && prove -r'
