import '../domain/tour.dart';

/// Hand-written Soho (London) content used by the mock generator.
///
/// Stops are tagged with interests; the generator picks the ones matching
/// the request, orders them into a walkable loop, and trims to duration.
class DemoTours {
  const DemoTours._();

  static Tour build(TourRequest req) {
    final wanted = req.interests.isEmpty ? Interest.values.toSet() : req.interests;

    // Score each stop by how many requested interests it matches, keep the
    // walk order (the list below is already a sensible loop through Soho).
    final scored = <(TourStop, int)>[
      for (final s in _sohoStops)
        (s, s.interests.intersection(wanted).length),
    ];
    var picked = scored.where((e) => e.$2 > 0).map((e) => e.$1).toList();
    if (picked.length < 3) {
      picked = _sohoStops.toList();
    }

    // Roughly 6 minutes of content + walking per stop.
    final maxStops = (req.durationMinutes / 6).round().clamp(3, _sohoStops.length);
    if (picked.length > maxStops) {
      // Prefer the best-matching stops, but restore walk order afterwards.
      final best = [...scored.where((e) => picked.contains(e.$1))]
        ..sort((a, b) => b.$2.compareTo(a.$2));
      final keep = best.take(maxStops).map((e) => e.$1).toSet();
      picked = _sohoStops.where(keep.contains).toList();
    }

    final theme = _themeFor(wanted);
    return Tour(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: theme.$1,
      subtitle: '${req.durationMinutes} min · ${picked.length} stops · Soho, London',
      neighbourhood: 'Soho',
      durationMinutes: req.durationMinutes,
      tone: req.tone,
      intro: _intro(req.tone, theme.$1, picked.first.name),
      outro: _outro(req.tone),
      stops: picked,
    );
  }

  static (String, String) _themeFor(Set<Interest> wanted) {
    if (wanted.length == 1) {
      return switch (wanted.first) {
        Interest.food => ('Soho, one bite at a time', 'food'),
        Interest.music => ('Soho: where the noise came from', 'music'),
        Interest.oddities => ('Soho oddities', 'oddities'),
        Interest.history => ('Soho, before the neon', 'history'),
        Interest.architecture => ('Soho in brick and glass', 'architecture'),
        Interest.nightlife => ('Soho after dark', 'nightlife'),
      };
    }
    return ('Soho, sideways', 'mixed');
  }

  static List<ScriptLine> _intro(Tone tone, String title, String firstStop) {
    switch (tone) {
      case Tone.playful:
        return [
          ScriptLine(Host.a, "Right, headphones in? Good. Welcome to $title. I'm Mara."),
          const ScriptLine(Host.b, "And I'm Theo, and I've been told to behave, so expect that to last about four minutes."),
          ScriptLine(Host.a, "We're walking you through Soho today. First stop is $firstStop. Follow the map, we'll keep talking, and shout when you get there."),
          const ScriptLine(Host.b, 'Not literally. Tap the button. People will stare.'),
        ];
      case Tone.curious:
        return [
          ScriptLine(Host.a, "Hello, and welcome to $title. I'm Mara."),
          const ScriptLine(Host.b, "I'm Theo. Soho is barely a square kilometre, and I still get lost in it every time."),
          ScriptLine(Host.a, "Which is sort of the point. We're heading to $firstStop first. Take your time, look up a lot, and let us know when you've arrived."),
        ];
      case Tone.deepDive:
        return [
          ScriptLine(Host.a, "Welcome to $title. I'm Mara, and over the next little while we're going to read Soho like a document."),
          const ScriptLine(Host.b, "I'm Theo. Soho was farmland until the 1670s. Everything you'll see today was built, rebuilt, or argued about since."),
          ScriptLine(Host.a, "Our first stop is $firstStop. Walk there with us, and we'll set the scene on the way."),
        ];
    }
  }

  static List<ScriptLine> _outro(Tone tone) {
    switch (tone) {
      case Tone.playful:
        return [
          const ScriptLine(Host.b, "And that's the walk. You survived Soho, and so did I, barely."),
          const ScriptLine(Host.a, 'Check your keepsake for the route, your photos, and how you did on the questions. Thanks for walking with us.'),
        ];
      case Tone.curious:
        return [
          const ScriptLine(Host.a, "That's our loop. Same streets you started on, hopefully a slightly different Soho."),
          const ScriptLine(Host.b, "Your route, your photos, and the sources for everything we said are in your keepsake. Thanks for coming along."),
        ];
      case Tone.deepDive:
        return [
          const ScriptLine(Host.a, "That closes the walk. Every claim we made today is cited in your keepsake, so you can go further."),
          const ScriptLine(Host.b, 'Thanks for walking with us. Soho rewards a second look.'),
        ];
    }
  }

  // ── Stops ─────────────────────────────────────────────────────────────────
  // Coordinates are real. Walk order: Soho Square → Greek St → Frith St →
  // Old Compton St → Wardour St → Berwick St → Broadwick St → Carnaby St.

  static const _sohoStops = <TourStop>[
    TourStop(
      id: 'soho-square',
      name: 'Soho Square',
      lat: 51.5155,
      lng: -0.1320,
      directionsHint: 'Head into the middle of Soho Square and find the little half-timbered hut.',
      interests: {Interest.oddities, Interest.history, Interest.architecture},
      script: [
        ScriptLine(Host.a, "So you're in Soho Square, and in the middle there's this tiny Tudor cottage. Looks like it's been here since Shakespeare."),
        ScriptLine(Host.b, "It hasn't. It's from 1925. And the square was laid out in the 1680s, so the hut is by far the youngest thing here that's trying to look old."),
        ScriptLine(Host.a, 'What is it for?'),
        ScriptLine(Host.b, "Officially, a gardener's tool shed. Under it was an electricity substation for a while. There's a persistent rumour about a tunnel to a nearby building, which nobody has ever produced evidence for."),
        ScriptLine(Host.a, 'And the statue?'),
        ScriptLine(Host.b, "Charles the Second. He's been here since 1681, though he went missing for about seventy years, sat in someone's garden in Harrow, and came back in 1938."),
      ],
      quiz: QuizQuestion(
        question: 'When was the mock-Tudor hut in the middle of Soho Square built?',
        options: ['1580s', '1780s', '1920s'],
        correctIndex: 2,
        explanation: "It's from 1925, built as a gardener's shed over what became an electrical substation.",
      ),
      photoPrompt: 'The Tudor hut, with the statue of Charles II if you can get both in.',
      sources: [
        Source(title: 'Soho Square — Wikipedia', url: 'https://en.wikipedia.org/wiki/Soho_Square'),
      ],
    ),
    TourStop(
      id: 'house-of-st-barnabas',
      name: 'House of St Barnabas',
      lat: 51.5151,
      lng: -0.1311,
      directionsHint: 'Walk to the south-east corner of the square. The big Georgian house on the corner of Greek Street is the one.',
      interests: {Interest.history, Interest.architecture, Interest.nightlife},
      script: [
        ScriptLine(Host.b, "Number one Greek Street. Built in 1746, and inside it's one of the best-preserved rococo interiors in London."),
        ScriptLine(Host.a, 'And outside it looks like every other Georgian house on the block.'),
        ScriptLine(Host.b, "That's the Georgian trick. Plain brick, all the money spent on plasterwork indoors. For a century and a half it was a homeless charity, since 1862."),
        ScriptLine(Host.a, "Now it's a members' club that funds the charity. Dickens is supposed to have based part of A Tale of Two Cities on the house and the little chapel round the back."),
        ScriptLine(Host.b, "Supposed to. There's a plaque and a lot of wishful thinking."),
      ],
      quiz: QuizQuestion(
        question: 'What has the House of St Barnabas been since 1862?',
        options: ['A bank', 'A homeless charity', 'A theatre'],
        correctIndex: 1,
        explanation: 'The charity moved in in 1862 and still owns the house; the club funds it.',
      ),
      photoPrompt: 'The front door and railings on Greek Street.',
      sources: [
        Source(title: 'House of St Barnabas — Wikipedia', url: 'https://en.wikipedia.org/wiki/House_of_St_Barnabas'),
      ],
    ),
    TourStop(
      id: 'maison-bertaux',
      name: 'Maison Bertaux',
      lat: 51.5137,
      lng: -0.1309,
      directionsHint: 'Walk south down Greek Street. Maison Bertaux is the blue-fronted patisserie on your right at number 28.',
      interests: {Interest.food, Interest.history},
      script: [
        ScriptLine(Host.a, "Maison Bertaux. This is the oldest patisserie in London, open since 1871."),
        ScriptLine(Host.b, 'Founded by a communard who fled Paris after the Commune collapsed. So the croissants are, technically, political refugees.'),
        ScriptLine(Host.a, "It's been run by the same two sisters since the eighties and it looks like nobody has redecorated since roughly then either."),
        ScriptLine(Host.b, "Which is the charm. Go in later. Get the éclair. Don't ask for oat milk."),
      ],
      quiz: QuizQuestion(
        question: 'In what year did Maison Bertaux open?',
        options: ['1871', '1921', '1961'],
        correctIndex: 0,
        explanation: 'It opened in 1871, making it the oldest patisserie in London.',
      ),
      photoPrompt: 'The blue shopfront, ideally with something in the window.',
      sources: [
        Source(title: 'Maison Bertaux — Wikipedia', url: 'https://en.wikipedia.org/wiki/Maison_Bertaux'),
      ],
    ),
    TourStop(
      id: 'bar-italia',
      name: 'Bar Italia & 22 Frith Street',
      lat: 51.5134,
      lng: -0.1315,
      directionsHint: 'Cut through to Frith Street and head south. Bar Italia is at 22, under the big clock.',
      interests: {Interest.food, Interest.history, Interest.music, Interest.nightlife},
      script: [
        ScriptLine(Host.b, "Bar Italia. Open since 1949, open until about four in the morning, and the espresso machine is older than most of the people using it."),
        ScriptLine(Host.a, "Look up at the plaque. In 1926, in the room above this café, John Logie Baird gave the first public demonstration of television."),
        ScriptLine(Host.b, 'To about fifty members of the Royal Institution, who watched a flickering face on a screen the size of a postcard.'),
        ScriptLine(Host.a, "And Ronnie Scott's is directly opposite. So this one stretch of Frith Street gave us television and Britain's most famous jazz club."),
        ScriptLine(Host.b, "Also the Pulp song. Bar Italia is the last track on Different Class. It's about being here at 5am, which, honestly, still happens."),
      ],
      quiz: QuizQuestion(
        question: 'What did John Logie Baird first demonstrate publicly above 22 Frith Street in 1926?',
        options: ['Radar', 'Television', 'The telephone'],
        correctIndex: 1,
        explanation: 'Baird showed a working television to members of the Royal Institution here in January 1926.',
      ),
      photoPrompt: 'The Bar Italia clock, or the Baird plaque above the door.',
      sources: [
        Source(title: 'Bar Italia — Wikipedia', url: 'https://en.wikipedia.org/wiki/Bar_Italia_(Soho)'),
        Source(title: 'John Logie Baird — Wikipedia', url: 'https://en.wikipedia.org/wiki/John_Logie_Baird'),
      ],
    ),
    TourStop(
      id: 'old-compton-street',
      name: 'Old Compton Street',
      lat: 51.5131,
      lng: -0.1318,
      directionsHint: 'A few steps further south and you hit Old Compton Street. Stop on the corner and look both ways.',
      interests: {Interest.nightlife, Interest.history, Interest.food},
      script: [
        ScriptLine(Host.a, "Old Compton Street. If Soho has a spine, this is it."),
        ScriptLine(Host.b, "Since the eighties it's been the centre of London's gay scene. The Admiral Duncan pub, just along there, was bombed in 1999 and reopened within weeks, deliberately unchanged."),
        ScriptLine(Host.a, "Before that, the street was the French quarter. Huguenot refugees in the seventeen hundreds, then Italians, then everyone."),
        ScriptLine(Host.b, "The Algerian Coffee Stores at 52 has been selling coffee since 1887. Same shop, same counter. It's one of the cheapest espressos in London and it's not even close."),
      ],
      quiz: QuizQuestion(
        question: 'Since when has the Algerian Coffee Stores been trading on Old Compton Street?',
        options: ['1887', '1947', '1987'],
        correctIndex: 0,
        explanation: 'It opened in 1887 and is still run from the same shop.',
      ),
      photoPrompt: 'The street looking west, with as many awnings and flags in frame as you can get.',
      sources: [
        Source(title: 'Old Compton Street — Wikipedia', url: 'https://en.wikipedia.org/wiki/Old_Compton_Street'),
        Source(title: 'Algerian Coffee Stores — Wikipedia', url: 'https://en.wikipedia.org/wiki/Algerian_Coffee_Stores'),
      ],
    ),
    TourStop(
      id: 'trident-studios',
      name: "Trident Studios, St Anne's Court",
      lat: 51.5141,
      lng: -0.1340,
      directionsHint: "Walk west along Old Compton Street, right up Wardour Street, then left into the narrow alley called St Anne's Court. Number 17.",
      interests: {Interest.music, Interest.oddities},
      script: [
        ScriptLine(Host.b, "This alley. Number 17. This was Trident Studios, and for about ten years it had the best sounding room in London."),
        ScriptLine(Host.a, 'Give me names.'),
        ScriptLine(Host.b, "Hey Jude was recorded here in 1968, because Trident had an eight-track before Abbey Road did. Bowie did Hunky Dory and Ziggy Stardust here. Queen did their first three albums. Elton John, Lou Reed, Genesis."),
        ScriptLine(Host.a, "And the piano. The Trident Bechstein. That's the piano on Hey Jude, on Life on Mars, and on Bohemian Rhapsody."),
        ScriptLine(Host.b, "Same instrument. In this alley. Next to what is now, I think, a nail bar."),
      ],
      quiz: QuizQuestion(
        question: 'Which Beatles single was recorded at Trident Studios in 1968?',
        options: ['Let It Be', 'Hey Jude', 'Penny Lane'],
        correctIndex: 1,
        explanation: 'Hey Jude was cut at Trident because it had an eight-track machine before Abbey Road.',
      ),
      photoPrompt: 'The plaque at number 17, or the whole alley looking down its length.',
      sources: [
        Source(title: 'Trident Studios — Wikipedia', url: 'https://en.wikipedia.org/wiki/Trident_Studios'),
      ],
    ),
    TourStop(
      id: 'berwick-street',
      name: 'Berwick Street Market',
      lat: 51.5137,
      lng: -0.1355,
      directionsHint: "Out the west end of St Anne's Court, cross Wardour Street and keep going to Berwick Street. Stand by the market stalls.",
      interests: {Interest.music, Interest.food, Interest.history},
      script: [
        ScriptLine(Host.a, "Berwick Street. There's been a market here since the seventeen hundreds, and it's one of the oldest street markets in London."),
        ScriptLine(Host.b, "It also, briefly, sold more records per square metre than anywhere in the country. Sister Ray, Reckless, Selectadisc, all along here."),
        ScriptLine(Host.a, "Which is why Oasis shot the cover of What's the Story Morning Glory here in 1995. Two men passing each other, right about where you're standing."),
        ScriptLine(Host.b, "One of them is the record's producer, Owen Morris, and he's holding the master tape. Which is either very confident or very stupid."),
      ],
      quiz: QuizQuestion(
        question: 'Which album cover was photographed on Berwick Street in 1995?',
        options: ["Oasis — (What's the Story) Morning Glory?", 'Blur — Parklife', 'Pulp — Different Class'],
        correctIndex: 0,
        explanation: 'The Morning Glory cover shows two men passing on Berwick Street; the DJ Sean Rowley and producer Owen Morris.',
      ),
      photoPrompt: 'Recreate the album cover: the street looking north, someone walking towards you.',
      sources: [
        Source(title: 'Berwick Street — Wikipedia', url: 'https://en.wikipedia.org/wiki/Berwick_Street'),
      ],
    ),
    TourStop(
      id: 'john-snow-pump',
      name: 'The John Snow pump',
      lat: 51.5133,
      lng: -0.1367,
      directionsHint: 'Head south on Berwick Street, then right onto Broadwick Street. Look for the pub called The John Snow and a pump with no handle outside.',
      interests: {Interest.history, Interest.oddities},
      script: [
        ScriptLine(Host.b, "A water pump with no handle. That missing handle is arguably the most important object in the history of public health."),
        ScriptLine(Host.a, "1854. Cholera kills over five hundred people in this neighbourhood in ten days. Everyone thinks it's bad air."),
        ScriptLine(Host.b, "John Snow, a doctor, maps the deaths house by house and they cluster around this pump. He persuades the parish to take the handle off. The outbreak stops."),
        ScriptLine(Host.a, "It's the birth of epidemiology, and there's a pub named after him. Snow was a teetotaller."),
        ScriptLine(Host.b, "He'd have been furious. Or he'd have appreciated the irony. Probably furious."),
      ],
      quiz: QuizQuestion(
        question: 'What did John Snow have removed from the Broad Street pump in 1854?',
        options: ['The handle', 'The spout', 'The sign'],
        correctIndex: 0,
        explanation: 'Removing the handle stopped people drawing contaminated water; the cholera outbreak ended.',
      ),
      photoPrompt: 'The handle-less pump with the pub sign behind it.',
      sources: [
        Source(title: '1854 Broad Street cholera outbreak — Wikipedia', url: 'https://en.wikipedia.org/wiki/1854_Broad_Street_cholera_outbreak'),
      ],
    ),
    TourStop(
      id: 'carnaby-street',
      name: 'Carnaby Street',
      lat: 51.5130,
      lng: -0.1392,
      directionsHint: 'Continue west along Broadwick Street until it opens onto Carnaby Street. Stand under the arch.',
      interests: {Interest.music, Interest.history, Interest.nightlife, Interest.architecture},
      script: [
        ScriptLine(Host.a, "Carnaby Street. In 1966 Time magazine put London on its cover as the swinging city, and this street was basically the illustration."),
        ScriptLine(Host.b, "Boutiques run by people in their twenties selling clothes nobody's parents would wear. The Who, the Small Faces, the Kinks all shopped here. Then the tourists came, and it got a bit theme-park."),
        ScriptLine(Host.a, "It's had a second life though. Kingly Court, the little courtyard off to the side, is proper again. Go eat there."),
        ScriptLine(Host.b, "And the name is nothing to do with anything glamorous. Karnaby House, a 1680s building, long gone. Nobody knows who Karnaby was."),
      ],
      quiz: QuizQuestion(
        question: 'Which magazine put "Swinging London" on its cover in 1966, making Carnaby Street famous worldwide?',
        options: ['Life', 'Time', 'Vogue'],
        correctIndex: 1,
        explanation: "Time's April 1966 cover story 'London: The Swinging City' did it.",
      ),
      photoPrompt: 'The Carnaby Street arch, looking down the street.',
      sources: [
        Source(title: 'Carnaby Street — Wikipedia', url: 'https://en.wikipedia.org/wiki/Carnaby_Street'),
      ],
    ),
  ];
}
