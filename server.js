import express from "express";
import nodemailer from "nodemailer";
import { fileURLToPath } from "node:url";
import path from "node:path";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const distPath = path.join(__dirname, "dist");

const app = express();
const port = Number.parseInt(process.env.PORT || "3000", 10);
const smtpHost = process.env.SMTP_HOST || "192.168.222.12";
const smtpPort = Number.parseInt(process.env.SMTP_PORT || "25", 10);
const smtpSecure = process.env.SMTP_SECURE === "true";
const mailFrom = process.env.MAIL_FROM || "post@skrivdet.no";
const mailTo = process.env.MAIL_TO || "post@skrivdet.no";

const transporter = nodemailer.createTransport({
  host: smtpHost,
  port: smtpPort,
  secure: smtpSecure,
  tls: {
    rejectUnauthorized: process.env.SMTP_REJECT_UNAUTHORIZED === "true",
  },
});

app.disable("x-powered-by");
app.use(express.json({ limit: "16kb" }));

function cleanField(value) {
  return typeof value === "string" ? value.trim().slice(0, 250) : "";
}

function isEmail(value) {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value);
}

app.post("/api/contact", async (request, response) => {
  const firstName = cleanField(request.body?.firstName);
  const lastName = cleanField(request.body?.lastName);
  const phone = cleanField(request.body?.phone);
  const email = cleanField(request.body?.email);

  if (!firstName || !lastName || !email || !isEmail(email)) {
    response.status(400).json({ message: "Fyll ut navn og en gyldig e-postadresse." });
    return;
  }

  const submittedAt = new Date().toISOString();
  const subject = `Ny henvendelse fra skrivdet.no: ${firstName} ${lastName}`;
  const text = [
    "Ny henvendelse fra kontaktskjemaet på skrivdet.no",
    "",
    `Fornavn: ${firstName}`,
    `Etternavn: ${lastName}`,
    `Telefon: ${phone || "Ikke oppgitt"}`,
    `E-post: ${email}`,
    `Tidspunkt: ${submittedAt}`,
  ].join("\n");

  try {
    await transporter.sendMail({
      from: mailFrom,
      to: mailTo,
      replyTo: email,
      subject,
      text,
    });

    response.json({ message: `Takk, ${firstName}! Vi tar kontakt så snart vi kan.` });
  } catch (error) {
    console.error("Contact form mail failed", error);
    response.status(502).json({
      message: "Beklager, vi fikk ikke sendt skjemaet akkurat nå. Prøv igjen litt senere.",
    });
  }
});

app.use("/assets", express.static(path.join(distPath, "assets"), { immutable: true, maxAge: "1y" }));
app.use(express.static(distPath, { index: false, maxAge: 0 }));

app.get(/.*/, (request, response) => {
  response.set("Cache-Control", "no-cache");
  response.sendFile(path.join(distPath, "index.html"));
});

app.listen(port, () => {
  console.log(`skrivDET website listening on port ${port}`);
});
