// Every kid- and parent-facing string in one place (phone-app.md "Copy and tone"), in every
// language the big screen can pick (config.language, contracts §2b). Both tables have exactly
// the same keys (test/copy.test.js). German is Swiss-friendly: "ss", never "ß".
import { LANGUAGES } from "@bebbikart/shared";

const en = {
  appName: "BebbiKart",
  offline: "Reconnecting…",
  create: {
    title: "Make your racer!",
    nameLabel: "Racer name",
    namePlaceholder: "e.g. Mila",
    driver: "Photo of the driver drawing",
    ride: "Photo of the ride drawing",
    retake: "Retake",
    tip: "Lay the paper flat, fill the frame, good light.",
    submit: "Make my racer!",
    uploading: "Sending your drawings…",
    needBoth: "We need both drawings.",
    cancel: "Keep my racer",
  },
  making: {
    queuedLines: [
      "Waiting in line…",
      "Your racer is next in the workshop!",
      "Warming up the crayons…",
    ],
    // Rotating lines per design stage (AssetJob.stage): looking, designing, critiquing, refining.
    lines: {
      looking: [
        "Studying your masterpiece…",
        "Counting every whisker…",
        "Mixing your crayon colours…",
        "Ooh, look at those wheels…",
        "Taking a really close look…",
      ],
      designing: [
        "Building your driver…",
        "Bolting on the wheels…",
        "Giving your driver a personality…",
        "Picking the perfect paint…",
        "Choosing a funny horn…",
      ],
      critiquing: [
        "Checking it against your drawing…",
        "Squinting very hard…",
        "Does it look like yours? Hmm…",
      ],
      refining: [
        "Adding the finishing touches…",
        "Polishing the paint…",
        "Tuning the horn…",
        "Pumping up the tyres…",
      ],
    },
    stageNames: { looking: "Look", designing: "Build", critiquing: "Check", refining: "Polish" },
    slow: "Making a racer takes about a minute.",
    review: "A grown-up is checking it, one moment.",
    failed: "We couldn't make your racer from these drawings.",
    failedHint: "Tell a grown-up what it says, then try again:",
    unknownError: "unknown error",
  },
  reject: {
    not_a_drawing: "That looks like a real photo. Please take a picture of the drawing!",
    real_person: "We can only use drawings, not photos of people. Try the drawing!",
    unreadable: "We couldn't see that one well. Try a closer, brighter photo!",
    empty_page: "That page looks empty! Take a photo of your drawing.",
    unsupported_file: "We couldn't open that picture. Try taking the photo again.",
    retakeDriver: "Retake the driver photo",
    retakeRide: "Retake the ride photo",
  },
  reveal: {
    lookUp: "Look at the big screen!",
    another: "Try another look",
    go: "Let's race!",
  },
  garage: {
    stars: "Stars",
    starsLeft: (n) =>
      n === 0 ? "All stars placed!" : n > 0 ? `Stars left: ${n}` : `Too many stars: ${-n}`,
    ways: "🛣️ Your stars choose the way",
    waysSteer: "Hands off, your kart goes this way. Steer to take the other one!",
    wayOn: (n, ability, way) => `${n} ${ability.toLowerCase()} stars: you ${way}!`,
    wayOff: (more, ability, way) =>
      `${more} more ${ability.toLowerCase()} ${more === 1 ? "star" : "stars"} and you ${way}`,
    best: "Best",
    bestLap: "Best lap",
    rank: "Rank",
    noBest: "No time yet",
    newDrawings: "New drawings",
    lookFailed: "Your new look didn't work:",
  },
  abilities: {
    speed: ["🚀", "Speed", "go fast on straights"],
    jump: ["🦘", "Jump", "fly over the ramp"],
    grip: ["🧲", "Grip", "stick to the road"],
    water: ["🌊", "Water", "zoom through the pond"],
    stability: ["🪨", "Stability", "don't get blown away"],
    bounce: ["🏀", "Bounce", "bounce back from bumps"],
  },
  forks: {
    ramp: {
      title: "The ramp",
      jump: ["🦘 Jump", "needs jump"],
      around: ["↪️ Around", "safe"],
      way: "fly over the ramp",
    },
    pond: {
      title: "The pond",
      water: ["🌊 Water", "needs water"],
      bridge: ["🌉 Bridge", "safe"],
      way: "splash through the pond",
    },
    crossing: {
      title: "The crossing",
      exposed: ["🌬️ Windy bridge", "fast in calm"],
      sheltered: ["🌳 Hedge path", "safe in wind"],
      way: "take the windy bridge",
    },
  },
  weather: {
    calm: "☀️ Sunny",
    rainWarn: "🌧️ Rain coming!",
    rain: "🌧️ Raining",
    windWarn: "🌬️ Wind coming!",
    wind: "🌬️ Windy",
  },
  run: {
    queued: "Lining up at the start…",
    getReady: "Get ready!",
    go: "GO!",
    padLabel: "Steering: slide your thumb left or right",
    steering: "👍 You steer",
    handsOff: "🤖 Driving by itself",
    steerHint: "Slide your thumb left or right to steer. Let go: your kart drives itself.",
    forkIn: (m) => `Fork in ${m} m`,
    forkHint: "Be on that side of the road when you get there!",
    arrowsHint: "Drive over the glowing arrows for a boost!",
    leave: "✕ Leave the race",
    leaveAsk: "Tap again to leave",
    leaving: "Leaving…",
    left: "You left the race. Join the line again whenever you like!",
  },
  result: {
    oops: "Oops!",
    pb: "New best! 🎉",
    finished: "Finished!",
    change: "Change & try again",
    bestLapTitle: "Best lap",
    section: "Section",
    time: "Time",
    vsBest: "vs best",
    fail: {
      off_track: "Off the road",
      flipped: "Flipped over",
      stuck: "Got stuck",
      timeout: "Out of time",
    },
    aborted: "The race was stopped",
    stretchesTitle: "Where the time went",
    vsYourBest: "vs your best",
    safeRoute: "🛣️",
    endedHere: "ended here",
    fasterHere: (who, s) => `${who} is ${s} s faster here`,
  },
  sections: { hills: "Hills", pond: "Pond", crossing: "Crossing", bends: "Bends" },
  setup: {
    title: (n) => `${n}'s setup`,
    close: "Close",
    you: "You",
    bestLap: "Best lap",
    bestTime: "Best time",
    setIn: { rain: "🌧️ set in the rain", wind: "🌬️ set in the wind", calm: "☀️ set in the sun" },
    hasAbility: (who, theirs, mine, name) => `${who} has ${theirs} ${name}, you have ${mine}`,
    tookRoute: (who, theirs, mine) => `${who} took ${theirs}, you took ${mine}`,
    fasterRoute: (who, route, s) =>
      `${who} takes the ${route.charAt(0).toLowerCase()}${route.slice(1)}: ${s} s faster`,
    decide: "What would you change? Try it, then beat them!",
    tapHint: "Tap a racer to see their setup",
  },
  map: {
    title: "🗺️ Track map",
    label: "Map of the track",
    missing: (track) => `No map for the track "${track}". Tell the game manager.`,
    tapHint: "Tap the map to find a stretch in the list",
    garageHint: "Tap a stretch: which star helps there?",
    picked: (name, star) => (star ? `${name}: ${star} helps here` : `${name}: the safe way round`),
    weatherHint: "🌧️ 🌬️ = the weather hits here hardest",
    rain: "🌧️",
    wind: "🌬️",
  },
  // Stretches per track (contracts §2d), as the result list names them.
  stretches: {
    countryside: {
      bumpy_road: "Bumpy hill road",
      kicker: "Big ramp",
      knoll_road: "Round the knoll",
      hilltop: "Hilltop straight",
      ford: "Pond ford",
      stone_bridge: "Stone bridge",
      causeway: "Windy causeway",
      hedge_lane: "Hedge path",
      rainbow_bends: "Rainbow bends",
    },
    village: {
      main_street: "Main street",
      kicker: "Ski jump",
      churchyard: "Round the church",
      church_hill: "Church hill",
      ford: "Duck pond ford",
      covered_bridge: "Covered bridge",
      farm: "Muddy farm track",
      cobbles: "Bumpy cobbles",
      ridge: "Windy ridge",
      alpbach: "Mountain stream",
      causeway: "Windy causeway",
      arcades: "Arcades",
      square: "Village square",
    },
  },
  // Duel mode (contracts §2i): the line, the champion, the two halves of the big screen.
  duel: {
    title: "👑 King of the hill",
    join: "Join the line",
    leave: "Leave the line",
    none: "No champion yet: the first lap takes the crown!",
    champion: (who, time) => `${who} holds the crown: ${time}`,
    mine: (time) => `Your time holds the crown: ${time}`,
    tries: (n) =>
      n === 0 ? "Nobody has tried to beat it yet" : n === 1 ? "1 try so far" : `${n} tries so far`,
    onTrack: "On the track",
    line: "In line",
    nobody: "Nobody is waiting: join and you race next!",
    place: (n) =>
      n === 1 ? "You're next!" : `You're ${n === 2 ? "2nd" : n === 3 ? "3rd" : `${n}th`} in line`,
    restHint: "You hold the crown, so the others go first.",
    skipped: "Your phone was offline at your turn. Join the line again!",
    side: { left: "🔴 You're on the left, in red", right: "🔵 You're on the right, in blue" },
    sideShort: { left: "🔴 left", right: "🔵 right" },
    newChampion: "👑 New champion!",
    short: (s, who) => `${s} s short of ${who}`,
    ownRecord: "👑 New record! The crown stays with you",
    ownShort: (s) => `${s} s short of your record. The crown stays with you`,
    noTime: (who) => `No time this lap: ${who} keeps the crown`,
    noTimeOwn: "No time this lap. The crown stays with you",
    noTimeNobody: "No time this lap: the crown is still free",
  },
  tabs: { garage: "🏎️ Garage", leaderboard: "🏆 Leaderboard" },
  paddock: {
    title: "Also here",
    making: "being made",
    ready: "ready",
    racing: "racing",
    photos: "taking photos",
  },
  sessionEnded: "This race is over! Thanks for racing. The next one starts on the big screen.",
  sessionIdle: "The race hasn't started yet.",
  quit: {
    button: "Quit",
    ask: "Leave the game? Your racer leaves the big screen and the leaderboard.",
    askRacing: "Leave the game? Your racer stops racing and leaves the big screen.",
    stay: "Keep playing",
    confirm: "Yes, quit",
    failed: "Couldn't quit, your racer is still in the game",
  },
  errors: {
    run_in_progress: "Your racer is still on the track.",
    session_not_running: "The race isn't open right now.",
    not_ready: "Your racer isn't ready yet.",
    reroll_limit: "That's all the new looks for now.",
    server_full: "The track is full right now.",
    invalid_build: "Set your stars again, they don't add up.",
    player_exists: "This phone already has a racer.",
    not_found: "Create your racer first.",
    bad_request: "That didn't work. Try again!",
    bad_message: "That didn't work. Try again!",
    unauthorized: "This phone isn't allowed to do that.",
    track_locked: "The track can't change during a race.",
    in_line: "You're already in the line!",
    generic: "Something went wrong. Try again!",
  },
};

const de = {
  appName: "BebbiKart",
  offline: "Verbinde neu…",
  create: {
    title: "Bau deinen Rennfahrer!",
    nameLabel: "Name des Rennfahrers",
    namePlaceholder: "z.B. Mila",
    driver: "Foto der Fahrer-Zeichnung",
    ride: "Foto der Fahrzeug-Zeichnung",
    retake: "Nochmal",
    tip: "Papier flach hinlegen, Bild ganz ausfüllen, gutes Licht.",
    submit: "Bau meinen Rennfahrer!",
    uploading: "Deine Zeichnungen werden gesendet…",
    needBoth: "Wir brauchen beide Zeichnungen.",
    cancel: "Meinen Rennfahrer behalten",
  },
  making: {
    queuedLines: [
      "Warte in der Schlange…",
      "Dein Rennfahrer ist als Nächstes in der Werkstatt!",
      "Die Farbstifte wärmen sich auf…",
    ],
    // Rotating lines per design stage (AssetJob.stage): looking, designing, critiquing, refining.
    lines: {
      looking: [
        "Wir bestaunen dein Meisterwerk…",
        "Wir zählen jedes Schnurrhaar…",
        "Wir mischen deine Farbstift-Farben…",
        "Oh, schau dir diese Räder an…",
        "Wir schauen ganz genau hin…",
      ],
      designing: [
        "Wir bauen deinen Fahrer…",
        "Wir schrauben die Räder an…",
        "Dein Fahrer bekommt eine Persönlichkeit…",
        "Wir suchen die perfekte Farbe aus…",
        "Wir wählen eine lustige Hupe…",
      ],
      critiquing: [
        "Wir vergleichen es mit deiner Zeichnung…",
        "Wir kneifen die Augen ganz fest zusammen…",
        "Sieht es aus wie deins? Hmm…",
      ],
      refining: [
        "Der letzte Schliff…",
        "Wir polieren den Lack…",
        "Wir stimmen die Hupe…",
        "Wir pumpen die Reifen auf…",
      ],
    },
    stageNames: {
      looking: "Schauen",
      designing: "Bauen",
      critiquing: "Prüfen",
      refining: "Polieren",
    },
    slow: "Ein Rennfahrer braucht etwa eine Minute.",
    review: "Ein Erwachsener schaut es kurz an, einen Moment.",
    failed: "Aus diesen Zeichnungen konnten wir keinen Rennfahrer bauen.",
    failedHint: "Sag einem Erwachsenen, was hier steht, und versuch es nochmal:",
    unknownError: "unbekannter Fehler",
  },
  reject: {
    not_a_drawing: "Das sieht aus wie ein echtes Foto. Bitte fotografiere die Zeichnung!",
    real_person:
      "Wir können nur Zeichnungen nehmen, keine Fotos von Menschen. Probier die Zeichnung!",
    unreadable: "Das konnten wir nicht gut sehen. Probier ein näheres, helleres Foto!",
    empty_page: "Die Seite sieht leer aus! Fotografiere deine Zeichnung.",
    unsupported_file: "Wir konnten das Bild nicht öffnen. Mach das Foto nochmal.",
    retakeDriver: "Fahrer-Foto nochmal machen",
    retakeRide: "Fahrzeug-Foto nochmal machen",
  },
  reveal: {
    lookUp: "Schau auf den grossen Bildschirm!",
    another: "Anderen Look probieren",
    go: "Los geht's!",
  },
  garage: {
    stars: "Sterne",
    starsLeft: (n) =>
      n === 0 ? "Alle Sterne verteilt!" : n > 0 ? `Sterne übrig: ${n}` : `Zu viele Sterne: ${-n}`,
    ways: "🛣️ Deine Sterne wählen den Weg",
    waysSteer: "Hände weg: Dein Kart fährt hier lang. Lenk, dann nimmst du den anderen Weg!",
    wayOn: (n, ability, way) => `${n} Sterne ${ability}: du ${way}!`,
    wayOff: (more, ability, way) =>
      `Noch ${more} ${more === 1 ? "Stern" : "Sterne"} ${ability} und du ${way}`,
    best: "Bestzeit",
    bestLap: "Beste Runde",
    rank: "Platz",
    noBest: "Noch keine Zeit",
    newDrawings: "Neue Zeichnungen",
    lookFailed: "Dein neuer Look hat nicht geklappt:",
  },
  abilities: {
    speed: ["🚀", "Tempo", "schnell auf Geraden"],
    jump: ["🦘", "Sprung", "flieg über die Rampe"],
    grip: ["🧲", "Grip", "kleb an der Strasse"],
    water: ["🌊", "Wasser", "flitz durch den Teich"],
    stability: ["🪨", "Stabilität", "lass dich nicht wegwehen"],
    bounce: ["🏀", "Federung", "spring nach Remplern zurück"],
  },
  forks: {
    ramp: {
      title: "Die Rampe",
      jump: ["🦘 Springen", "braucht Sprung"],
      around: ["↪️ Aussen herum", "sicher"],
      way: "fliegst über die Rampe",
    },
    pond: {
      title: "Der Teich",
      water: ["🌊 Wasser", "braucht Wasser"],
      bridge: ["🌉 Brücke", "sicher"],
      way: "spritzt durch den Teich",
    },
    crossing: {
      title: "Die Kreuzung",
      exposed: ["🌬️ Windige Brücke", "schnell ohne Wind"],
      sheltered: ["🌳 Heckenweg", "sicher bei Wind"],
      way: "nimmst die windige Brücke",
    },
  },
  weather: {
    calm: "☀️ Sonnig",
    rainWarn: "🌧️ Regen kommt!",
    rain: "🌧️ Es regnet",
    windWarn: "🌬️ Wind kommt!",
    wind: "🌬️ Windig",
  },
  run: {
    queued: "Aufstellen am Start…",
    getReady: "Bereit machen!",
    go: "LOS!",
    padLabel: "Lenken: Schieb den Daumen nach links oder rechts",
    steering: "👍 Du lenkst",
    handsOff: "🤖 Fährt allein",
    steerHint:
      "Schieb den Daumen nach links oder rechts zum Lenken. Lass los: Dein Kart fährt allein.",
    forkIn: (m) => `Gabelung in ${m} m`,
    forkHint: "Sei auf dieser Strassenseite, wenn du dort ankommst!",
    arrowsHint: "Fahr über die Leuchtpfeile für einen Boost!",
    leave: "✕ Rennen verlassen",
    leaveAsk: "Nochmal tippen zum Verlassen",
    leaving: "Verlasse…",
    left: "Du hast das Rennen verlassen. Stell dich wieder an, wann du willst!",
  },
  result: {
    oops: "Hoppla!",
    pb: "Neue Bestzeit! 🎉",
    finished: "Im Ziel!",
    change: "Ändern & nochmal",
    bestLapTitle: "Beste Runde",
    section: "Abschnitt",
    time: "Zeit",
    vsBest: "zur Bestzeit",
    fail: {
      off_track: "Von der Strasse abgekommen",
      flipped: "Überschlagen",
      stuck: "Stecken geblieben",
      timeout: "Zeit abgelaufen",
    },
    aborted: "Das Rennen wurde gestoppt",
    stretchesTitle: "Wo die Zeit blieb",
    vsYourBest: "zu deiner Bestzeit",
    safeRoute: "🛣️",
    endedHere: "hier war Schluss",
    fasterHere: (who, s) => `${who} ist hier ${s} s schneller`,
  },
  sections: { hills: "Hügel", pond: "Teich", crossing: "Kreuzung", bends: "Kurven" },
  setup: {
    title: (n) => `Setup von ${n}`,
    close: "Schliessen",
    you: "Du",
    bestLap: "Beste Runde",
    bestTime: "Bestzeit",
    setIn: {
      rain: "🌧️ im Regen gefahren",
      wind: "🌬️ im Wind gefahren",
      calm: "☀️ bei Sonne gefahren",
    },
    hasAbility: (who, theirs, mine, name) => `${who} hat ${theirs} ${name}, du hast ${mine}`,
    tookRoute: (who, theirs, mine) => `${who} nahm ${theirs}, du ${mine}`,
    fasterRoute: (who, route, s) => `${who} nimmt: ${route}, ${s} s schneller`,
    decide: "Was würdest du ändern? Probier es und schlag die Zeit!",
    tapHint: "Tipp auf jemanden, um das Setup zu sehen",
  },
  map: {
    title: "🗺️ Streckenkarte",
    label: "Karte der Strecke",
    missing: (track) => `Keine Karte für die Strecke "${track}". Sag es der Spielleitung.`,
    tapHint: "Tipp auf die Karte, um den Abschnitt in der Liste zu finden",
    garageHint: "Tipp auf einen Abschnitt: Welcher Stern hilft dort?",
    picked: (name, star) => (star ? `${name}: hier hilft ${star}` : `${name}: der sichere Weg`),
    weatherHint: "🌧️ 🌬️ = hier trifft das Wetter am stärksten",
    rain: "🌧️",
    wind: "🌬️",
  },
  stretches: {
    countryside: {
      bumpy_road: "Holperstrasse",
      kicker: "Grosse Schanze",
      knoll_road: "Um den Hügel",
      hilltop: "Hügelkuppe",
      ford: "Teichfurt",
      stone_bridge: "Steinbrücke",
      causeway: "Windiger Damm",
      hedge_lane: "Heckenweg",
      rainbow_bends: "Regenbogenkurven",
    },
    village: {
      main_street: "Hauptstrasse",
      kicker: "Sprungschanze",
      churchyard: "Um die Kirche",
      church_hill: "Kirchhügel",
      ford: "Furt im Ententeich",
      covered_bridge: "Gedeckte Brücke",
      farm: "Matschiger Feldweg",
      cobbles: "Holperpflaster",
      ridge: "Windiger Grat",
      alpbach: "Alpbach",
      causeway: "Windiger Damm",
      arcades: "Lauben",
      square: "Dorfplatz",
    },
  },
  duel: {
    title: "👑 König vom Hügel",
    join: "In die Schlange",
    leave: "Aus der Schlange",
    none: "Noch kein Champion: die erste Runde holt die Krone!",
    champion: (who, time) => `${who} hat die Krone: ${time}`,
    mine: (time) => `Deine Zeit hält die Krone: ${time}`,
    tries: (n) =>
      n === 0
        ? "Noch niemand hat es versucht"
        : n === 1
          ? "1 Versuch bisher"
          : `${n} Versuche bisher`,
    onTrack: "Auf der Strecke",
    line: "In der Schlange",
    nobody: "Niemand wartet: stell dich an und du fährst gleich!",
    place: (n) => (n === 1 ? "Du bist als Nächstes dran!" : `Du bist ${n}. in der Schlange`),
    restHint: "Du hast die Krone, also fahren zuerst die anderen.",
    skipped: "Dein Handy war offline, als du dran warst. Stell dich nochmal an!",
    side: { left: "🔴 Du fährst links, in Rot", right: "🔵 Du fährst rechts, in Blau" },
    sideShort: { left: "🔴 links", right: "🔵 rechts" },
    newChampion: "👑 Neuer Champion!",
    short: (s, who) => `${s} s langsamer als ${who}`,
    ownRecord: "👑 Neuer Rekord! Die Krone bleibt bei dir",
    ownShort: (s) => `${s} s langsamer als dein Rekord. Die Krone bleibt bei dir`,
    noTime: (who) => `Keine Zeit in dieser Runde: ${who} behält die Krone`,
    noTimeOwn: "Keine Zeit in dieser Runde. Die Krone bleibt bei dir",
    noTimeNobody: "Keine Zeit in dieser Runde: die Krone ist noch frei",
  },
  tabs: { garage: "🏎️ Garage", leaderboard: "🏆 Rangliste" },
  paddock: {
    title: "Auch hier",
    making: "wird gebaut",
    ready: "bereit",
    racing: "fährt",
    photos: "macht Fotos",
  },
  sessionEnded:
    "Dieses Rennen ist vorbei! Danke fürs Mitfahren. Das nächste startet auf dem grossen Bildschirm.",
  sessionIdle: "Das Rennen hat noch nicht angefangen.",
  quit: {
    button: "Aufhören",
    ask: "Spiel verlassen? Dein Rennfahrer verschwindet vom grossen Bildschirm und aus der Rangliste.",
    askRacing:
      "Spiel verlassen? Dein Rennfahrer hört auf zu fahren und verschwindet vom grossen Bildschirm.",
    stay: "Weiterspielen",
    confirm: "Ja, aufhören",
    failed: "Aufhören hat nicht geklappt, dein Rennfahrer ist noch im Spiel",
  },
  errors: {
    run_in_progress: "Dein Rennfahrer ist noch auf der Strecke.",
    session_not_running: "Das Rennen ist gerade nicht offen.",
    not_ready: "Dein Rennfahrer ist noch nicht fertig.",
    reroll_limit: "Das waren alle neuen Looks für jetzt.",
    server_full: "Die Strecke ist gerade voll.",
    invalid_build: "Verteil deine Sterne nochmal, sie gehen nicht auf.",
    player_exists: "Dieses Handy hat schon einen Rennfahrer.",
    not_found: "Bau zuerst deinen Rennfahrer.",
    bad_request: "Das hat nicht geklappt. Versuch es nochmal!",
    bad_message: "Das hat nicht geklappt. Versuch es nochmal!",
    unauthorized: "Dieses Handy darf das nicht.",
    track_locked: "Die Strecke kann während eines Rennens nicht wechseln.",
    in_line: "Du stehst schon in der Schlange!",
    generic: "Etwas ist schiefgelaufen. Versuch es nochmal!",
  },
};

export const COPY_TABLES = { en, de };

/** Shown before the server has said which language to speak, so in both. */
export const BOOT_COPY = {
  connecting: "Connecting to the race… · Verbinde mit dem Rennen…",
  failed: "Couldn't reach the race · Keine Verbindung zum Rennen",
};

/**
 * Wraps a table so a missing key throws instead of reading undefined: no silent gaps, and no
 * English standing in for German. Arrays and functions are returned as they are.
 */
function strict(table, path) {
  return new Proxy(table, {
    get(target, key) {
      if (typeof key === "symbol") return target[key];
      if (!Object.hasOwn(target, key)) throw new Error(`copy: no text for "${path}.${key}"`);
      const v = target[key];
      return v && typeof v === "object" && !Array.isArray(v) ? strict(v, `${path}.${key}`) : v;
    },
  });
}
const STRICT = { en: strict(en, "en"), de: strict(de, "de") };
const NOT_YET = new Proxy(
  {},
  {
    get(_, key) {
      throw new Error(`copy: "${String(key)}" read before the server sent the language`);
    },
  },
);

/** The table in use. A live binding: setLanguage swaps it and every screen reads the new one. */
export let COPY = NOT_YET;
export let language = null;

/** Picks the table for config.language. An unknown language throws (no fallback). */
export function setLanguage(lang) {
  if (lang === language) return;
  if (!LANGUAGES.includes(lang)) throw new Error(`copy: unknown language "${lang}"`);
  language = lang;
  COPY = STRICT[lang];
  if (globalThis.document) document.documentElement.lang = lang;
}

/** Text for a REST or WS error: the translated line for its code, else the code and message. */
export function errorText(err) {
  if (Object.hasOwn(COPY_TABLES[language].errors, err.code)) return COPY.errors[err.code];
  return `${COPY.errors.generic} (${err.code}: ${err.message})`;
}
