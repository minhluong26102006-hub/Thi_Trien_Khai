FROM python:3.12-alpine

WORKDIR /app

RUN addgroup -g 10001 -S appgroup &&     adduser -u 10001 -S appuser -G appgroup &&     mkdir -p /var/log &&     touch /var/log/alerts.log &&     chown -R appuser:appgroup /var/log/alerts.log /app

COPY --chown=appuser:appgroup server.py .

USER appuser

EXPOSE 9099

CMD ["python", "server.py"]
