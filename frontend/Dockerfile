FROM node:22-alpine AS build
WORKDIR /workspace

COPY frontend/package.json frontend/package-lock.json ./
RUN npm ci

ARG VITE_API_BASE_URL=/api
ENV VITE_API_BASE_URL=${VITE_API_BASE_URL}
COPY frontend/ ./
RUN npm run build

FROM nginx:1.27-alpine
COPY --from=build /workspace/dist /usr/share/nginx/html
COPY nginx/nginx.conf /etc/nginx/nginx.conf

EXPOSE 80
HEALTHCHECK --interval=10s --timeout=3s --start-period=10s --retries=5 \
    CMD wget --quiet --output-document=/dev/null http://127.0.0.1/ || exit 1
