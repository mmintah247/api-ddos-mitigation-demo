docker network create proxy

docker-compose up -d --force-recreate


docker-compose up -d --build --force-recreate

//payload
wrk -t10 -c50000 -d30s --latency http://165.232.42.130:5001/balance/


http://127.0.0.1:5001/balance/1056824615097

http://165.232.42.130:5001/balance/1056824615097


docker ps
docker logs -f api


docker-compose up -d --force-recreate loki


docker compose -f docker-compose.vulnerable.yml up -d --build --force-recreate



docker compose -f docker-compose.vulnerable.yml down


docker-compose -f docker-compose.mitigated.yml up -d --build

docker-compose -f docker-compose.mitigated.yml down
docker-compose -f docker-compose.mitigated.yml up -d --build --force-recreate




#cloud UAT
wrk -t2 -c5000 -d120s --latency http://165.232.42.130:5001/balance/

#webpage
http://165.232.42.130:8081/

#database

##phymyadmin
http://165.232.42.130:8080/

#api
http://165.232.42.130:5001/balance/1005880649042