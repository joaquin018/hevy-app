# Build first: cd frontend; flutter build web --release
FROM nginx:stable-alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY build/web /usr/share/nginx/html
EXPOSE 80
