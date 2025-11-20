# API DDoS Mitigation Demo

## Docker Network Setup

```bash
docker network create proxy
```

## Load Testing

### Payload Test
```bash
wrk -t2 -c2000 -d120s --latency http://206.189.121.14:5001/balance/
```

### Balance Endpoint
```bash
http://165.232.42.130:5001/balance/1056824615097
```

## Docker Compose Operations

### Restart Services
```bash
docker compose -f docker-compose.mitigated.yml down
docker compose -f docker-compose.mitigated.yml up -d --build --force-recreate
```

## Monitoring

### Check API Logs
```bash
docker logs -f --tail 10 api
```

### Check Docker Stats
```bash
docker stats api
```

## Observability Dashboard
- URL: https://167.71.118.73:8443/


