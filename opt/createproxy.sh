docker network create proxy

docker-compose up -d --force-recreate


docker-compose up -d --build --force-recreate

//payload
wrk -t10 -c10000 -d30s --latency http://127.0.0.1:5001/balance/


http://127.0.0.1:5001/balance/1056824615097


docker ps
docker logs -f api


docker-compose up -d --force-recreate loki


docker-compose -f docker-compose.vulnerable.yml up -d --build

docker-compose -f docker-compose.vulnerable.yml down


docker-compose -f docker-compose.mitigated.yml up -d --build

docker-compose -f docker-compose.mitigated.yml down
docker-compose -f docker-compose.mitigated.yml up -d --build --force-recreate