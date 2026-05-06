import { useEffect, useMemo, useState } from "react";
import { Link, Route, Routes, useLocation } from "react-router-dom";

const asset = (path) => `${import.meta.env.BASE_URL}${path.replace(/^\//, "")}`;
const brandName = "skrivDET";
const brandLogoHorizontal = asset("assets/skrivdet-v2.png");
const brandLogoStacked = asset("assets/skrivdet-v3.png");

const storeLinks = [
  {
    alt: "Last ned på App Store",
    available: true,
    href: "https://www.wix.com/templateslp/studio-external-link",
    src: asset("assets/apple-store.png"),
  },
  {
    alt: "Last ned på Google Play",
    available: false,
    href: "https://www.wix.com/templateslp/studio-external-link",
    src: asset("assets/google-play.png"),
  },
];

const phoneScreens = [
  { duration: 4400, src: asset("assets/phone-screen-1-splash.png") },
  { duration: 3000, src: asset("assets/phone-screen-2-recording.png") },
  { duration: 3000, src: asset("assets/phone-screen-3-templates.png") },
];

const featureCards = [
  {
    delay: 0,
    description: "Skreddersydde formater for avdelingsmøter, 1-til-1 eller tekniske diskusjoner.",
    title: "Smarte maler",
  },
  {
    delay: 220,
    description: "Markedsledende nøyaktighet, selv med dialekter og fagterminologi.",
    title: "Mist aldri et ord",
  },
  {
    delay: 440,
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
    icon: "wallet",
    text: "Laget for å spare tid uten å gjøre innkjøpet tungt eller komplisert.",
    title: "Rimelig",
  },
  {
    delay: 110,
    icon: "shield",
    text: "Et tydelig alternativ for virksomheter som ikke kan kompromisse på sikkerhet.",
    title: "Best personvern",
  },
  {
    delay: 200,
    icon: "refresh",
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
    name: "Teamleder i helsetjenesten",
    quote: "skrivDET gjør det enklere å være til stede i samtalen og få dokumentasjonen ferdig raskt etterpå.",
  },
  {
    delay: 110,
    image: asset("assets/customer-michelle.png"),
    name: "Pilotkunde i offentlig sektor",
    quote: "Det viktigste for oss er kontroll på dataene, og at oppsummeringen faktisk blir nyttig for teamet.",
  },
  {
    delay: 200,
    image: asset("assets/customer-ben.jpg"),
    name: "Fagleder i helse",
    quote: "Vi sparer tid hver uke fordi skrivDET tar hånd om strukturen, uten at vi mister oversikten.",
  },
];

function PricingIcon({ type }) {
  const commonProps = {
    "aria-hidden": "true",
    fill: "none",
    stroke: "currentColor",
    strokeLinecap: "round",
    strokeLinejoin: "round",
    strokeWidth: "1.8",
    viewBox: "0 0 24 24",
  };

  if (type === "wallet") {
    return (
      <svg {...commonProps}>
        <path d="M4 8.5A2.5 2.5 0 0 1 6.5 6H18a2 2 0 0 1 2 2v1H6.5A2.5 2.5 0 0 0 4 11.5z" />
        <path d="M4 11.5A2.5 2.5 0 0 1 6.5 9H20v7a2 2 0 0 1-2 2H6.5A2.5 2.5 0 0 1 4 15.5z" />
        <path d="M16.5 13.5h3" />
      </svg>
    );
  }

  if (type === "shield") {
    return (
      <svg {...commonProps}>
        <path d="M12 3l6 2.5v5.7c0 4.2-2.5 8-6 9.8-3.5-1.8-6-5.6-6-9.8V5.5z" />
        <path d="M9.5 12.3l1.8 1.8 3.4-3.6" />
      </svg>
    );
  }

  return (
    <svg {...commonProps}>
      <path d="M20 7v5h-5" />
      <path d="M4 17v-5h5" />
      <path d="M7.5 8.5A6 6 0 0 1 18 7" />
      <path d="M16.5 15.5A6 6 0 0 1 6 17" />
    </svg>
  );
}

function useSiteEffects() {
  useEffect(() => {
    const mediaQuery = window.matchMedia("(prefers-reduced-motion: reduce)");
    const prefersReducedMotion = mediaQuery.matches;
    const hero = document.querySelector("#hero");
    const body = document.body;
    const parallaxNodes = [...document.querySelectorAll("[data-parallax]")];
    const parallaxSections = [...document.querySelectorAll("[data-section-parallax]")];
    const animatedNodes = [...document.querySelectorAll("[data-animate]")];
    const howSection = document.querySelector(".how-section");

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

    let howSectionObserver;
    if (howSection && !prefersReducedMotion) {
      howSectionObserver = new IntersectionObserver(
        (entries) => {
          entries.forEach((entry) => {
            if (!entry.isIntersecting) {
              return;
            }

            entry.target.classList.add("is-sequenced");
            howSectionObserver?.unobserve(entry.target);
          });
        },
        {
          threshold: 0.5,
          rootMargin: "-8% 0px -18% 0px",
        }
      );

      howSectionObserver.observe(howSection);
    } else if (howSection) {
      howSection.classList.add("is-sequenced");
    }

    return () => {
      body.classList.remove("motion-enabled", "is-scrolled");
      window.removeEventListener("scroll", syncScrollState);
      observer?.disconnect();
      howSectionObserver?.disconnect();
      cleanupPointer();
      removeParallaxListeners.forEach((cleanup) => cleanup());
    };
  }, []);
}

function SiteHeader() {
  const [isOpen, setIsOpen] = useState(false);
  const location = useLocation();

  useEffect(() => {
    const closeMenu = () => setIsOpen(false);
    window.addEventListener("hashchange", closeMenu);
    return () => window.removeEventListener("hashchange", closeMenu);
  }, []);

  return (
    <header className="site-header">
      <div className="container header-inner">
        <a className="brand" href="#top" aria-label={`${brandName} hjem`}>
          <img className="brand-logo" src={brandLogoHorizontal} alt={brandName} />
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
          <a href="#hvordan" onClick={() => setIsOpen(false)}>Hvordan det fungerer</a>
          <a href="#sikkerhet" onClick={() => setIsOpen(false)}>Sikkerhet</a>
          <a href="#priser" onClick={() => setIsOpen(false)}>Priser</a>
          <a href="#kontakt" onClick={() => setIsOpen(false)}>Kontakt</a>
          <Link
            to="/system-architecture"
            className={location.pathname === "/system-architecture" ? "is-active" : undefined}
            onClick={() => setIsOpen(false)}
          >
            Systemarkitektur
          </Link>
          <a href="#download" onClick={() => setIsOpen(false)}>
            Last ned
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
            <img className="brand-logo brand-logo-footer" src={brandLogoHorizontal} alt={brandName} />
          </a>
          <p>© 2026 by Kvasetech AS</p>
        </div>
        <div>
          <h3>Retningslinjer</h3>
          <Link to="/system-architecture">Systemarkitektur</Link>
          <Link to="/privacy-policy">Personvernerklæring</Link>
          <Link to="/accessibility-statement">Tilgjengelighetserklæring</Link>
        </div>
        <div>
          <h3>Videre</h3>
          <a href={`${import.meta.env.BASE_URL}#kontakt`}>Kontakt oss</a>
          <Link to="/system-architecture">Se systemarkitektur</Link>
        </div>
      </div>
    </footer>
  );
}

function HomePage() {
  const [activePhoneScreen, setActivePhoneScreen] = useState(0);
  const [previousPhoneScreen, setPreviousPhoneScreen] = useState(0);
  const [message, setMessage] = useState("");

  useSiteEffects();

  useEffect(() => {
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      return undefined;
    }

    const timeoutId = window.setTimeout(() => {
      setPreviousPhoneScreen(activePhoneScreen);
      setActivePhoneScreen((current) => (current + 1) % phoneScreens.length);
    }, phoneScreens[activePhoneScreen].duration);

    return () => window.clearTimeout(timeoutId);
  }, [activePhoneScreen]);

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
                skrivDET tar notatene for deg med ekstrem presisjon og norsk datasikkerhet.
              </p>
              <div className="hero-actions" id="download">
                {storeLinks.map((link) => (
                  link.available ? (
                    <a
                      key={link.alt}
                      className="store-link"
                      href={link.href}
                      target="_blank"
                      rel="noreferrer"
                    >
                      <img src={link.src} alt={link.alt} />
                    </a>
                  ) : (
                    <span
                      key={link.alt}
                      className="store-link store-link-disabled"
                      aria-disabled="true"
                      title="Android-versjonen er ikke tilgjengelig ennå"
                    >
                      <img src={link.src} alt={link.alt} />
                    </span>
                  )
                ))}
              </div>
            </div>

            <div className="hero-visual" aria-hidden="true" data-animate="up-lg" data-delay="120">
              <div className="phone-stack" data-parallax="0.14">
                <div
                  className={`phone-viewport${previousPhoneScreen === 0 && activePhoneScreen == 1 ? " is-splash-handoff" : ""}`}
                >
                  {phoneScreens.map((screen, index) => (
                    <img
                      key={screen.src}
                      className={`phone-screen${index === activePhoneScreen ? " is-active" : ""}`}
                      src={screen.src}
                      alt=""
                    />
                  ))}
                </div>
                <img className="phone-frame" src={asset("assets/phone-frame.png")} alt="" />
                <div className="phone-indicators">
                  {phoneScreens.map((screen, index) => (
                    <span
                      key={`indicator-${screen.src}`}
                      className={`phone-indicator${index === activePhoneScreen ? " is-active" : ""}`}
                    />
                  ))}
                </div>
              </div>
            </div>
          </div>
        </section>

        <section className="section about-section" id="om">
          <div className="container">
            <div className="section-heading" data-animate="up">
              <p className="eyebrow">Det som pleide å ta timer, tar nå sekunder</p>
              <h2>skrivDET ferdigstiller dokumentasjonen din idet møtet er over.</h2>
            </div>
            <div className="info-grid">
              <article className="card card-large" data-animate="left">
                <h3>Ferdig dokumentasjon, automatisk</h3>
                <p>
                  Slipp notatblokken og vær 100 % til stede. skrivDET fanger samtalen og
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
                  Velg formålet med møtet før du starter, og la skrivDET trekke ut
                  beslutninger, ansvarsområder og oppgaver i et ryddig dokument.
                </p>
              </article>
            </div>
          </div>
        </section>

        <section className="section how-section" id="hvordan" data-section-parallax="-0.045">
          <div className="container">
            <div className="section-heading" data-animate="up">
              <p className="eyebrow">Hvordan det fungerer</p>
              <h2>Tre grunner til at referatet blir enklere å stole på.</h2>
            </div>
            <div className="feature-grid">
              {featureCards.map((card) => (
                <article
                  key={card.title}
                  className="feature-card how-feature-card"
                  style={{ "--enter-delay": `${card.delay}ms` }}
                >
                  <h3>{card.title}</h3>
                  <p>{card.description}</p>
                </article>
              ))}
            </div>
          </div>
        </section>

        <section className="section security-section" id="sikkerhet" data-section-parallax="0.065">
          <div className="container split-layout">
            <div data-animate="left">
              <p className="eyebrow">Best når det kommer til sikkerhet og personvern</p>
              <h2>Digital suverenitet og kontroll over egne data.</h2>
              <p>
                skrivDET prosesserer alt lokalt eller på norske servere. Mens konkurrenter
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
            <div className="illustration-wrap security-illustration-wrap" data-animate="up-lg" data-delay="120">
              <img
                className="security-illustration"
                src={asset("assets/security-illustration.png")}
                alt="Illustrasjon for personvern og sikkerhet"
                data-parallax="0.12"
              />
            </div>
          </div>
        </section>

        <section className="section pricing-section" id="priser" data-section-parallax="0.05">
          <div className="container">
            <div className="section-heading" data-animate="up">
              <p className="eyebrow">Enkelt å ta i bruk. Enkelt å stole på.</p>
              <h2>skrivDET er laget for å passe inn i hverdagen, ikke for å komplisere den.</h2>
            </div>
            <div className="pricing-grid">
              {pricingCards.map((card) => (
                <article key={card.title} className="pricing-card" data-animate="up" data-delay={card.delay}>
                  <span className="pricing-symbol" aria-hidden="true">
                    <PricingIcon type={card.icon} />
                  </span>
                  <h3>{card.title}</h3>
                  <p>{card.text}</p>
                </article>
              ))}
            </div>
          </div>
        </section>

        <section className="section partners-section">
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

        <section className="section contact-section" id="kontakt">
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
              <button className="button contact-submit" type="submit">Send</button>
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

function ArchitecturePage() {
  return (
    <>
      <SiteHeader />
      <main className="page-shell architecture-shell">
        <article className="page-card architecture-card">
          <img className="page-brandmark" src={brandLogoStacked} alt={brandName} />
          <h1>Systemdesign og arkitektur</h1>
          <p>
            Denne oversikten viser skrivDETs overordnede nettverksarkitektur og dataflyt mellom
            klient, internett, sikkerhetsgrense, interne tjenester og eksterne AI-tilbydere.
          </p>
          <a
            className="architecture-link"
            href={asset("assets/system-architecture.png")}
            target="_blank"
            rel="noreferrer"
          >
            Åpne bildet i full størrelse
          </a>
          <figure className="architecture-figure">
            <img
              className="architecture-image"
              src={asset("assets/system-architecture.png")}
              alt="skrivDET systemdesign og arkitektur med nettverksarkitektur og dataflyt"
            />
          </figure>
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
                personvernerklæringen fra skrivDET eller Kvasetech AS.
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
        <Route path="/system-architecture" element={<ArchitecturePage />} />
      </Routes>
    </>
  );
}
