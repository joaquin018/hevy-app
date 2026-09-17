FROM oven/bun:1.4.2-alpine
WORKDIR /app
COPY package.json bun.lock ./
RUN bun install --frozen-lockfile --production
COPY *.ts ./
EXPOSE 3000
CMD ["bun", "index.ts"]
