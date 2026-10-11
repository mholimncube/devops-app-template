# ============================================================
# Stage 1: Build stage
# ============================================================
# This stage is where you would run npm build, dotnet publish, etc.
# For static HTML, there's nothing to build, but we keep the pattern
# so the template works for future apps that need a build step.

FROM docker.io/library/nginx:1.27-alpine AS build

WORKDIR /app

# Copy source files
COPY src/ ./src/

# ============================================================
# Stage 2: Runtime stage
# ============================================================
# This is what actually ships. It contains only the runtime
# and the built artifact. Smaller image, smaller attack surface.

FROM docker.io/library/nginx:1.27-alpine AS runtime

# Add labels for traceability
LABEL org.opencontainers.image.title="devops-app-template"
LABEL org.opencontainers.image.description="Static hello world app for pipeline validation"
LABEL org.opencontainers.image.source="https://github.com/mholimncube/devops-app-template"

# Copy the built artifact from the build stage
COPY --from=build /app/src/ /usr/share/nginx/html/

# nginx listens on 80 by default
EXPOSE 80

# Health check (Kubernetes uses its own, but this helps for docker/podman runs)
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -q --spider http://localhost/ || exit 1

# nginx default entrypoint runs the server
CMD ["nginx", "-g", "daemon off;"]