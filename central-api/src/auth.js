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
