export default function Home() {
  return (
    <main
      style={{
        minHeight: "100dvh",
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        justifyContent: "center",
        padding: "2rem",
        textAlign: "center",
      }}
    >
      <h1
        style={{
          fontSize: "clamp(2rem, 6vw, 4rem)",
          fontWeight: 700,
          letterSpacing: "-0.02em",
          lineHeight: 1.1,
        }}
      >
        CutSense
      </h1>
      <p
        style={{
          marginTop: "1rem",
          fontSize: "1.125rem",
          color: "var(--muted)",
          maxWidth: "32ch",
        }}
      >
        Messy recording in. Polished video out.
      </p>
      <p
        style={{
          marginTop: "2rem",
          fontSize: "0.875rem",
          color: "var(--muted)",
          opacity: 0.6,
        }}
      >
        Coming soon to iOS.
      </p>
    </main>
  );
}
