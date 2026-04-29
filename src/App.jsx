import { useEffect, useMemo, useState } from "react";
import { Link, Route, Routes, useLocation } from "react-router-dom";

const asset = (path) => `${import.meta.env.BASE_URL}${path.replace(/^\//, "")}`;

const storeLinks = [
  {
    alt: "Last ned på App Store",
    href: "https://www.wix.com/templateslp/studio-external-link",
    src: asset("assets/apple-store.png"),
  },
  {
    alt: "Last ned på Google Play",
    href: "https://www.wix.com/templateslp/studio-external-link",
    src: asset("assets/google-play.png"),
  },
];

const featureCards = [
  {
    delay: 20,
    description: "Skreddersydde formater for avdelingsmøter, 1-til-1 eller tekniske diskusjoner.",
    title: "Smarte maler",
  },
  {
    delay: 110,
    description: "Markedsledende nøyaktighet, selv med dialekter og fagterminologi.",
    title: "Mist aldri et ord",
  },
  {
    delay: 200,
    description: "Se nøyaktig hvilke data som behandles og hvor de lagres til enhver tid.",
    title: "Full åpenhet",
  },
];

const securityCards = [
  {
    icon: asset("assets/icon-affordable.png"),
    text: "Lokal databehandling med tydelig eierskap til informasjonen.",
    title: "Faktisk GDPR-etterlevelse",
  },
  {
    icon: asset("assets/icon-subscription.png"),
    text: "Data lagres i norske datasentre med høy grad av kontroll.",
    title: "Fri fra Cloud Act-trussel",
  },
  {
    icon: asset("assets/icon-affordable.png"),
    text: "Bedriftsløsninger bygget rundt norsk lov og norsk infrastruktur.",
    title: "Data i Norge",
  },
  {
    icon: asset("assets/icon-subscription.png"),
    text: "Full åpenhet rundt behandling, lagring og tilgang til data.",
    title: "Best på personvern",
  },
];

const pricingCards = [
  {
    delay: 20,
    icon: asset("assets/icon-affordable.png"),
    index: "(01)",
    text: "Laget for å spare tid uten å gjøre innkjøpet tungt eller komplisert.",
    title: "Rimelig",
  },
  {
    delay: 110,
    icon: asset("assets/privacy-illustration.png"),
    index: "(02)",
    text: "Et tydelig alternativ for virksomheter som ikke kan kompromisse på sikkerhet.",
    title: "Best personvern",
  },
  {
    delay: 200,
    icon: asset("assets/icon-subscription.png"),
    index: "(03)",
    text: "Velg selv modellen som passer best for teamet ditt.",
    title: "Kjøp eller abonnement",
  },
];

const partnerLogos = [
  { alt: "Imoge", parallax: "0.08", src: asset("assets/partner-imoge.png") },
  { alt: "Stella Maris", parallax: "0.1", src: asset("assets/partner-stella-maris.png") },
  { alt: "Gasparyan", parallax: "0.12", src: asset("assets/partner-gasparyan.png") },
  { alt: "Partnerlogo", parallax: "0.09", src: asset("assets/partner-frame93.png") },
];

const testimonials = [
  {
    delay: 20,
    image: asset("assets/customer-ola.jpg"),
    name: "Ola Normann",
    quote: "Utrolig enkelt å bruke. Vi bruker det til alt, og sparer enormt med tid.",
  },
  {
    delay: 110,
    image: asset("assets/customer-michelle.png"),
    name: "Referanse kommer",
    quote: "Flere kundehistorier og tilbakemeldinger publiseres snart.",
  },
  {
    delay: 200,
    image: asset("assets/customer-ben.jpg"),
    name: "Kundehistorie kommer",
    quote: "Vi legger til flere kundeeksempler så snart de er klare.",
  },
];

function useSiteEffects() {
  useEffect(() => {
    const mediaQuery = window.matchMedia("(prefers-reduced-motion: reduce)");
    const prefersReducedMotion = mediaQuery.matches;
    const hero = document.querySelector("#hero");
    const body = document.body;
    const parallaxNodes = [...document.querySelectorAll("[data-parallax]")];
    const parallaxSections = [...document.querySelectorAll("[data-section-parallax]")];
    const animatedNodes = [...document.querySelectorAll("[data-animate]")];

    if (!prefersReducedMotion) {
      body.classList.add("motion-enabled");
    } else {
      body.classList.remove("motion-enabled");
    }

    const syncScrollState = () => {
      body.classList.toggle("is-scrolled", window.scrollY > 12);
    };

    syncScrollState();
    window.addEventListener("scroll", syncScrollState, { passive: true });

    animatedNodes.forEach((node) => {
      const delay = node.getAttribute("data-delay");
      if (delay) {
        node.style.setProperty("--enter-delay", `${delay}ms`);
      }
    });

    let observer;
    if (animatedNodes.length && !prefersReducedMotion) {
      observer = new IntersectionObserver(
        (entries) => {
          entries.forEach((entry) => {
            if (!entry.isIntersecting) {
              return;
            }

            entry.target.classList.add("is-visible");
            observer?.unobserve(entry.target);
          });
        },
        {
          threshold: 0.16,
          rootMargin: "0px 0px -8% 0px",
        }
      );

      animatedNodes.forEach((node) => observer.observe(node));
    } else {
      animatedNodes.forEach((node) => node.classList.add("is-visible"));
    }

    let cleanupPointer = () => {};
    if (hero && !prefersReducedMotion && window.matchMedia("(pointer: fine)").matches) {
      let frameRequested = false;
      let targetX = 0;
      let targetY = 0;
      let currentX = 0;
      let currentY = 0;

      const applyParallax = () => {
        currentX += (targetX - currentX) * 0.14;
        currentY += (targetY - currentY) * 0.14;

        hero.style.setProperty("--hero-shift-x", `${currentX.toFixed(2)}px`);
        hero.style.setProperty("--hero-shift-y", `${currentY.toFixed(2)}px`);

        if (Math.abs(targetX - currentX) > 0.15 || Math.abs(targetY - currentY) > 0.15) {
          window.requestAnimationFrame(applyParallax);
          return;
        }

        currentX = targetX;
        currentY = targetY;
        frameRequested = false;
      };

      const requestPointerParallax = () => {
        if (frameRequested) {
          return;
        }

        frameRequested = true;
        window.requestAnimationFrame(applyParallax);
      };

      const handleMouseMove = (event) => {
        const rect = hero.getBoundingClientRect();
        const normalizedX = (event.clientX - rect.left) / rect.width - 0.5;
        const normalizedY = (event.clientY - rect.top) / rect.height - 0.5;

        targetX = normalizedX * 18;
        targetY = normalizedY * 14;
        requestPointerParallax();
      };

      const handleMouseLeave = () => {
        targetX = 0;
        targetY = 0;
        requestPointerParallax();
      };

      hero.addEventListener("mousemove", handleMouseMove);
      hero.addEventListener("mouseleave", handleMouseLeave);

      cleanupPointer = () => {
        hero.removeEventListener("mousemove", handleMouseMove);
        hero.removeEventListener("mouseleave", handleMouseLeave);
      };
    }

    const removeParallaxListeners = [];

    if (parallaxNodes.length && !prefersReducedMotion) {
      const parallaxState = parallaxNodes.map((node) => ({
        current: 0,
        node,
        target: 0,
      }));
      let parallaxFrame = false;

      const measureParallax = () => {
        const viewportCenter = window.innerHeight / 2;

        parallaxState.forEach((entry) => {
          const speed = Number(entry.node.getAttribute("data-parallax")) || 0.1;
          const maxOffset = entry.node.closest(".hero") ? 40 : 30;
          const rect = entry.node.getBoundingClientRect();
          const elementCenter = rect.top + rect.height / 2;
          const distance = elementCenter - viewportCenter;
          entry.target = Math.max(-maxOffset, Math.min(maxOffset, distance * -speed));
        });
      };

      const updateParallax = () => {
        let needsMoreFrames = false;

        parallaxState.forEach((entry) => {
          entry.current += (entry.target - entry.current) * 0.16;
          entry.node.style.setProperty("--parallax-y", `${entry.current.toFixed(2)}px`);

          if (Math.abs(entry.target - entry.current) > 0.15) {
            needsMoreFrames = true;
          }
        });

        if (needsMoreFrames) {
          window.requestAnimationFrame(updateParallax);
          return;
        }

        parallaxState.forEach((entry) => {
          entry.current = entry.target;
          entry.node.style.setProperty("--parallax-y", `${entry.current.toFixed(2)}px`);
        });

        parallaxFrame = false;
      };

      const requestParallaxUpdate = () => {
        measureParallax();

        if (parallaxFrame) {
          return;
        }

        parallaxFrame = true;
        window.requestAnimationFrame(updateParallax);
      };

      requestParallaxUpdate();
      window.addEventListener("scroll", requestParallaxUpdate, { passive: true });
      window.addEventListener("resize", requestParallaxUpdate);
      removeParallaxListeners.push(() => {
        window.removeEventListener("scroll", requestParallaxUpdate);
        window.removeEventListener("resize", requestParallaxUpdate);
      });
    }

    if (parallaxSections.length && !prefersReducedMotion) {
      const sectionState = parallaxSections.map((section) => ({
        current: 0,
        section,
        target: 0,
      }));
      let sectionFrame = false;

      const measureSectionParallax = () => {
        const viewportCenter = window.innerHeight / 2;

        sectionState.forEach((entry) => {
          const speed = Number(entry.section.getAttribute("data-section-parallax")) || 0.05;
          const rect = entry.section.getBoundingClientRect();
          const sectionCenter = rect.top + rect.height / 2;
          const distance = sectionCenter - viewportCenter;
          entry.target = Math.max(-44, Math.min(44, distance * -speed));
        });
      };

      const updateSectionParallax = () => {
        let needsMoreFrames = false;

        sectionState.forEach((entry) => {
          entry.current += (entry.target - entry.current) * 0.14;
          entry.section.style.setProperty("--section-parallax-y", `${entry.current.toFixed(2)}px`);

          if (Math.abs(entry.target - entry.current) > 0.15) {
            needsMoreFrames = true;
          }
        });

        if (needsMoreFrames) {
          window.requestAnimationFrame(updateSectionParallax);
          return;
        }

        sectionState.forEach((entry) => {
          entry.current = entry.target;
          entry.section.style.setProperty("--section-parallax-y", `${entry.current.toFixed(2)}px`);
        });

        sectionFrame = false;
      };

      const requestSectionUpdate = () => {
        measureSectionParallax();

        if (sectionFrame) {
          return;
        }

        sectionFrame = true;
        window.requestAnimationFrame(updateSectionParallax);
      };

      requestSectionUpdate();
      window.addEventListener("scroll", requestSectionUpdate, { passive: true });
      window.addEventListener("resize", requestSectionUpdate);
      removeParallaxListeners.push(() => {
        window.removeEventListener("scroll", requestSectionUpdate);
        window.removeEventListener("resize", requestSectionUpdate);
      });
    }

    return () => {
      body.classList.remove("motion-enabled", "is-scrolled");
      window.removeEventListener("scroll", syncScrollState);
      observer?.disconnect();
      cleanupPointer();
      removeParallaxListeners.forEach((cleanup) => cleanup());
    };
  }, []);
}

function SiteHeader() {
  const [isOpen, setIsOpen] = useState(false);

  useEffect(() => {
    const closeMenu = () => setIsOpen(false);
    window.addEventListener("hashchange", closeMenu);
    return () => window.removeEventListener("hashchange", closeMenu);
  }, []);

  return (
    <header className="site-header">
      <div className="container header-inner">
        <a className="brand" href="#top" aria-label="Ulfy hjem">
          <span className="brand-mark">U</span>
          <span>Ulfy</span>
        </a>
        <button
          className="menu-toggle"
          type="button"
          aria-expanded={isOpen}
          aria-controls="site-nav"
          onClick={() => setIsOpen((open) => !open)}
        >
          Meny
        </button>
        <nav id="site-nav" className={`site-nav${isOpen ? " is-open" : ""}`} aria-label="Hovedmeny">
          <a href="#om" onClick={() => setIsOpen(false)}>Om</a>
          <a href="#priser" onClick={() => setIsOpen(false)}>Produkter og priser</a>
          <a href="#hvordan" onClick={() => setIsOpen(false)}>Hvordan virker dette?</a>
          <a className="button button-small" href="#download" onClick={() => setIsOpen(false)}>
            Last ned Ulfy
          </a>
        </nav>
      </div>
    </header>
  );
}

function SiteFooter() {
  return (
    <footer className="site-footer" data-animate="fade">
      <div className="container footer-grid">
        <div>
          <a className="brand footer-brand" href="#top">
            <span className="brand-mark">U</span>
            <span>Ulfy</span>
          </a>
          <p>© 2026 by Kvasetech AS</p>
        </div>
        <div>
          <h3>Retningslinjer</h3>
          <Link to="/privacy-policy">Personvernerklæring</Link>
          <Link to="/accessibility-statement">Tilgjengelighetserklæring</Link>
        </div>
        <div>
          <h3>Sosiale medier</h3>
          <a href="https://www.facebook.com/WixStudio" target="_blank" rel="noreferrer">Facebook</a>
          <a href="https://www.instagram.com/wixstudio" target="_blank" rel="noreferrer">Instagram</a>
        </div>
      </div>
    </footer>
  );
}

function HomePage() {
  const [message, setMessage] = useState("");

  useSiteEffects();

  const formFields = useMemo(
    () => [
      { label: "Fornavn", name: "firstName", required: true, type: "text" },
      { label: "Etternavn", name: "lastName", required: true, type: "text" },
      { label: "Telefon", name: "phone", required: false, type: "tel" },
      { label: "E-post", name: "email", required: true, type: "email" },
    ],
    []
  );

  const handleSubmit = (event) => {
    event.preventDefault();
    const formData = new FormData(event.currentTarget);
    const firstName = formData.get("firstName")?.toString().trim() || "der";
    setMessage(`Takk, ${firstName}! Skjemaet er lagret lokalt i denne statiske kopien.`);
    event.currentTarget.reset();
  };

  return (
    <>
      <SiteHeader />
      <main id="top">
        <section className="hero" id="hero" data-section-parallax="0.11">
          <div className="container hero-grid">
            <div className="hero-copy" data-animate="left">
              <p className="eyebrow">Hver samtale, perfekt oppsummer</p>
              <h1>Bruk tiden din på jobben, ikke på papirarbeid.</h1>
              <p className="lead">
                Vi tar notatene for deg med ekstrem presisjon og norsk datasikkerhet.
              </p>
              <div className="hero-actions" id="download">
                {storeLinks.map((link) => (
                  <a
                    key={link.alt}
                    className="store-link"
                    href={link.href}
                    target="_blank"
                    rel="noreferrer"
                  >
                    <img src={link.src} alt={link.alt} />
                  </a>
                ))}
              </div>
            </div>

            <div className="hero-visual" aria-hidden="true" data-animate="up-lg" data-delay="120">
              <div className="phone-stack" data-parallax="0.14">
                <div className="phone-viewport">
                  <img className="phone-screen" src={asset("assets/phone-screenshot.png")} alt="" />
                </div>
                <img className="phone-frame" src={asset("assets/phone-frame.png")} alt="" />
              </div>
            </div>
          </div>
        </section>

        <section className="section" id="om">
          <div className="container">
            <div className="section-heading" data-animate="up">
              <p className="eyebrow">Det som pleide å ta timer, tar nå sekunder</p>
              <h2>Ulfy ferdigstiller dokumentasjonen din idet møtet er over.</h2>
            </div>
            <div className="info-grid">
              <article className="card card-large" data-animate="left">
                <p>
                  Slipp notatblokken og vær 100 % til stede. Ulfy fanger samtalen og
                  strukturerer referatet automatisk – enten det er snakk om strategimøter
                  eller pasientsamtaler.
                </p>
                <p>
                  Spar inntil 40 minutter etterarbeid hver dag og få mer tid til
                  kjerneoppgavene dine.
                </p>
              </article>
              <article className="card" data-animate="up" data-delay="80">
                <h3>Små friksjoner bort</h3>
                <p>Fra løs prat til ferdig handlingsplan – helt automatisk.</p>
              </article>
              <article className="card" data-animate="up" data-delay="160">
                <h3>Struktur fra start</h3>
                <p>
                  Velg formålet med møtet før du starter, og la Ulfy trekke ut
                  beslutninger, ansvarsområder og oppgaver i et ryddig dokument.
                </p>
              </article>
            </div>
          </div>
        </section>

        <section className="section section-alt" id="hvordan" data-section-parallax="-0.045">
          <div className="container">
            <div className="section-heading" data-animate="up">
              <p className="eyebrow">Hvordan det fungerer</p>
              <h2>Tre grunner til at referatet blir enklere å stole på.</h2>
            </div>
            <div className="feature-grid">
              {featureCards.map((card) => (
                <article key={card.title} className="feature-card" data-animate="up" data-delay={card.delay}>
                  <h3>{card.title}</h3>
                  <p>{card.description}</p>
                </article>
              ))}
            </div>
          </div>
        </section>

        <section className="section security-section" data-section-parallax="0.065">
          <div className="container split-layout">
            <div data-animate="left">
              <p className="eyebrow">Best når det kommer til sikkerhet og personvern</p>
              <h2>Digital suverenitet og kontroll over egne data.</h2>
              <p>
                Ulfy prosesserer alt lokalt eller på norske servere. Mens konkurrenter
                bruker amerikanske skytjenester underlagt CLOUD Act, er budskapet her
                tydelig: absolutt digital suverenitet og full kontroll over egne data.
              </p>
              <div className="bullet-grid">
                {securityCards.map((card) => (
                  <article key={card.title} className="mini-card">
                    <img src={card.icon} alt="" />
                    <div>
                      <h3>{card.title}</h3>
                      <p>{card.text}</p>
                    </div>
                  </article>
                ))}
              </div>
            </div>
            <div className="illustration-wrap" data-animate="up-lg" data-delay="120">
              <img
                src={asset("assets/privacy-illustration.png")}
                alt="Illustrasjon for personvern og sikkerhet"
                data-parallax="0.12"
              />
            </div>
          </div>
        </section>

        <section className="section section-alt" id="priser" data-section-parallax="0.05">
          <div className="container">
            <div className="section-heading" data-animate="up">
              <p className="eyebrow">Simple. Easy. Healthy.</p>
              <h2>Here to support you every step of the way.</h2>
            </div>
            <div className="pricing-grid">
              {pricingCards.map((card) => (
                <article key={card.index} className="pricing-card" data-animate="up" data-delay={card.delay}>
                  <span className="pricing-index">{card.index}</span>
                  <img src={card.icon} alt="" />
                  <h3>{card.title}</h3>
                  <p>{card.text}</p>
                </article>
              ))}
            </div>
          </div>
        </section>

        <section className="section">
          <div className="container split-layout partners-layout">
            <div data-animate="left">
              <p className="eyebrow">Samarbeid og infrastruktur</p>
              <h2>Samarbeid med ledende selskaper innen IT-infrastruktur</h2>
              <p>
                Gjennom partnerskap med ledende norske IT-infrastrukturselskaper sørger
                vi for at dine data lagres og behandles i Norge.
              </p>
              <p>
                Dette sikrer bedriftsløsninger som følger norsk lov og ivaretar høyeste
                grad av datasikkerhet.
              </p>
            </div>
            <div className="partner-grid" data-animate="fade" data-delay="120">
              {partnerLogos.map((logo) => (
                <img key={logo.alt} src={logo.src} alt={logo.alt} data-parallax={logo.parallax} />
              ))}
            </div>
          </div>
        </section>

        <section className="section testimonials-section">
          <div className="container">
            <div className="section-heading" data-animate="up">
              <p className="eyebrow">Dette sier kundene våre</p>
              <h2>Tillit bygges i praksis.</h2>
            </div>
            <div className="testimonial-grid">
              {testimonials.map((testimonial) => (
                <article
                  key={testimonial.name}
                  className="testimonial-card"
                  data-animate="up"
                  data-delay={testimonial.delay}
                >
                  <img src={testimonial.image} alt={testimonial.name === "Ola Normann" ? testimonial.name : "Kundeportrett"} />
                  <blockquote>“{testimonial.quote}”</blockquote>
                  <p>— {testimonial.name}</p>
                </article>
              ))}
            </div>
          </div>
        </section>

        <section className="section contact-section">
          <div className="container split-layout">
            <div data-animate="left">
              <p className="eyebrow">Vi er her til å hjelpe deg</p>
              <h2>Har du spørsmål? Trenger hjelp?</h2>
              <p>Skriv inn din kontaktinformasjon og vi tar kontakt.</p>
            </div>
            <form className="contact-form" id="contact-form" data-animate="up-lg" data-delay="80" onSubmit={handleSubmit}>
              {formFields.map((field) => (
                <label key={field.name}>
                  <span>{field.label}</span>
                  <input type={field.type} name={field.name} required={field.required} />
                </label>
              ))}
              <button className="button" type="submit">Send</button>
              <p className="form-message" id="form-message" aria-live="polite">{message}</p>
            </form>
          </div>
        </section>
      </main>
      <SiteFooter />
    </>
  );
}

function PolicyPage({ title, children }) {
  return (
    <>
      <SiteHeader />
      <main className="page-shell">
        <article className="page-card">
          <h1>{title}</h1>
          {children}
          <Link className="back-link" to="/">
            Tilbake til forsiden
          </Link>
        </article>
      </main>
    </>
  );
}

function ScrollToTop() {
  const location = useLocation();

  useEffect(() => {
    window.scrollTo(0, 0);
  }, [location.pathname]);

  return null;
}

export default function App() {
  return (
    <>
      <ScrollToTop />
      <Routes>
        <Route path="/" element={<HomePage />} />
        <Route
          path="/privacy-policy"
          element={
            <PolicyPage title="Personvernerklæring">
              <p>
                Denne lokale kopien gjenskaper strukturen fra Wix-siden, men samler ikke inn eller
                sender personopplysninger noe sted. Kontaktskjemaet lagres kun lokalt i nettleseren
                for demonstrasjon.
              </p>
              <p>
                Ved en produksjonslansering bør denne siden erstattes med den endelige
                personvernerklæringen fra Ulfy eller Kvasetech AS.
              </p>
            </PolicyPage>
          }
        />
        <Route
          path="/accessibility-statement"
          element={
            <PolicyPage title="Tilgjengelighetserklæring">
              <p>
                Denne React-versjonen er bygget med semantiske HTML-elementer, tastaturnavigerbar
                meny og støtte for redusert bevegelse der det er mulig.
              </p>
              <p>
                Hvis dere publiserer siden offentlig, anbefales en egen tilgjengelighetsgjennomgang
                med kontrastkontroll, skjermlesertest og mobiltest før lansering.
              </p>
            </PolicyPage>
          }
        />
      </Routes>
    </>
  );
}
