import jwt from "jsonwebtoken";

export function requireEtlToken(req, res, next) {
  const header = req.headers.authorization || "";
  const [scheme, token] = header.split(" ");

  if (scheme !== "Bearer" || !token) {
    return res.status(401).json({ error: "missing_bearer_token" });
  }

  try {
    const claims = jwt.verify(token, process.env.JWT_SECRET, {
      issuer: process.env.JWT_ISSUER,
      audience: process.env.JWT_AUDIENCE,
      algorithms: ["HS256"]
    });

    if (!claims.facility_id || claims.scope !== "etl:write") {
      return res.status(403).json({ error: "invalid_token_scope" });
    }

    req.etl = claims;
    return next();
  } catch {
    return res.status(401).json({ error: "invalid_token" });
  }
}

export function requireAdminToken(req, res, next) {
  const expectedToken = process.env.ADMIN_TOKEN;
  if (!expectedToken) {
    return res.status(503).json({ error: "admin_token_not_configured" });
  }

  const header = req.headers.authorization || "";
  const [scheme, token] = header.split(" ");
  const adminToken = token || req.headers["x-admin-token"];

  if ((scheme && scheme !== "Bearer") || !adminToken) {
    return res.status(401).json({ error: "missing_admin_token" });
  }

  if (adminToken !== expectedToken) {
    return res.status(403).json({ error: "invalid_admin_token" });
  }

  return next();
}
