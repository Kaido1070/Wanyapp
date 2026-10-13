// Generated from Wany client algorithms. No WebView, DOM, or remote code execution.
const pendingRequests = new Map(); let requestSequence = 0;
function request(path, method='GET', body=null) {
 return new Promise((resolve,reject)=>{const id=String(++requestSequence);pendingRequests.set(id,{resolve,reject});nativeRequest(id,path,method,JSON.stringify(body));});
}
function settleRequest(id,text,error) { const p=pendingRequests.get(id);if(!p)return;pendingRequests.delete(id);if(error)p.reject(new Error(error));else {try{p.resolve(JSON.parse(text));}catch(e){p.reject(e);}} }
const memoryStorage=new Map();
const sessionStorage={getItem:k=>memoryStorage.get(k)||null,setItem:(k,v)=>memoryStorage.set(k,v)};
let timerSequence=0;const timers=new Map();
function setTimeout(fn,ms) {const id=String(++timerSequence);timers.set(id,fn);nativeTimer(id,ms);return id;}
function clearTimeout(id) {timers.delete(id);}
function fireTimer(id) {const f=timers.get(id);timers.delete(id);if(f)f();}
function query(path,values) {return '/api/source/'+path+'?'+Object.entries(values).filter(([,v])=>v!==undefined).map(([k,v])=>encodeURIComponent(k)+'='+encodeURIComponent(v)).join('&');}
const sourceService={
 isSourceKey:key=>Boolean(key&&/^(mt|tx|aq|sz|xs|ml|az):/.test(key)),
 recent:(source,page=1)=>request(query('recent',{source,page})),
 latest:(source,page=1)=>request(query('latest',{source,page})),
 popular:(source,page=1)=>request(query('popular',{source,page})),
 releaseHistory:chapters=>request(query('release-history',{chapters:[...new Set(chapters)].filter(Number.isFinite).slice(0,80).join(',')})),
 resolve:async keys=>keys.length?(await request(query('resolve',{keys:keys.join(',')}))).items:[],
 getSeries:async key=>(await request(query('series',{key}))).item,
};
const userDataService={
 getPersonalizationState:()=>request('/api/personalization-state'),
 getLists:async()=>(await request('/api/lists')).lists||[],
 getList:async id=>{const r=await request('/api/lists/'+encodeURIComponent(id));return {...r.list,items:r.items||[]};},
 getReadChapterPairs:async pairs=>{const out=[];for(let i=0;i<pairs.length;i+=40){const r=await request('/api/personalization-state','POST',{chapters:pairs.slice(i,i+40)});out.push(...(r.read||[]));}return out;}
};

const {sourceEnglishTitle} = (()=>{
const mangaTimeEnglishTitles = {
    "47": "47 Хромосом",
    "20th-century-boys": "20th Century Boys",
    "365-days-to-the-wedding": "365 Days to the Wedding",
    "a-dragonslayer-s-peerless-regression": "A Dragonslayer's Peerless Regression",
    "a-dragonslayers-peerless-regression": "A Dragonslayer's Peerless Regression",
    "a-journal-of-my-father": "A Journal Of My Father",
    "a-returners-magic-should-bespecial": "A Returner's Magic Should Be Special",
    "a-secretly-capable-child-is-seeking-for-her-dad": "Secretly Strong and Searching for My Daddy",
    "a-spy-s-survival-in-the-demonic-cult": "A Spy's Survival in the Demonic Cult",
    "a-transmigrators-privilege": "A Transmigrator's Privilege",
    "a-wimps-strategy-guide-to-conquer-the-tower": "A Wimp’s Strategy Guide to Conquer the Tower",
    "academys-genius-swordmaster": "Academy's Genius Swordmaster",
    "administrator-kang-jin-lee": "Administrator Kang Jin Lee",
    "after-becoming-a-dumpling-the-villain-family-all-wants-to-kill-me": "Turned a Toddler: The Villain Family Wants Me Dead!",
    "akari": "Akari",
    "aku-no-higan": "Beyond Evil",
    "all-hail-the-sect-leader": "All Hail the Sect Leader",
    "alpen-rose": "Alpen Rose",
    "amata": "Amata",
    "amelia-no-koukiteki-romance": "Amelia no Koukiteki Romance",
    "an-equation-without-wrong-answers": "An Equation with No Wrong Answers",
    "ana-no-mujina": "Ana no Mujina",
    "animeta": "Animeta!",
    "anne-no-aijou": "Anne no Aijou",
    "anne-no-seishun": "Anne no Seishun",
    "ao-ashi": "Aoashi",
    "apocalyptic-chef-awakening": "Apocalyptic Chef Awakening",
    "apocalyptic-super-farm": "Apocalyptic Super Farm",
    "archmage-transcending-through-regression": "Archmage Transcending Through Regression",
    "astral-pet-store": "Astral Pet Store",
    "attack-on-titan": "Attack on Titan",
    "attack-on-titan-before-the-fall": "Attack on Titan: Before the Fall",
    "attack-on-titan-junior-high": "Attack on Titan: Junior High",
    "baby-steps": "Baby Steps",
    "bad-born-blood": "Bad Born Blood",
    "bad-boy": "Bad Boy",
    "baki-gaiden-kenjin-2": "Baki Gaiden: Kenjin",
    "baki-revenge-tokyo": "Baki: Revenge Tokyo",
    "barakamon": "Barakamon",
    "beastars": "BEASTARS",
    "beastly-things": "Beastly Things",
    "became-a-medieval-fantasy-wizard": "Became a Medieval Fantasy Wizard",
    "beyblade-burst": "Beyblade Burst",
    "beyond-the-bad-dream": "Beyond the Bad Dream...",
    "black-butler": "Black Butler",
    "black-clover": "Black Clover",
    "black-terror": "Black Terror",
    "bleach-digital-colored": "Bleach - Digital Colored Comics",
    "bleach-official-colored": "Bleach (Official Colored)",
    "blue-box": "Blue Box",
    "blue-lock": "Blue Lock",
    "blue-lock-episode-nagi": "Blue Lock - Episode Nagi",
    "boruto-naruto-next-generation": "Boruto: Naruto Next Generations",
    "boruto-two-blue-vortex": "Boruto: Two Blue Vortex",
    "boukyaku-battery": "Oblivion Battery",
    "breakup": "Breakup",
    "bug-player": "Bug Player",
    "bungou-stray-dogs-the-day-i-picked-up-dazai": "Bungou Stray Dogs: The Day I Picked Up Dazai",
    "burn-the-witch": "Burn the Witch",
    "call-of-the-night-paradise-arc": "Call of the Night: Paradise Arc",
    "captain-tsubasa-world-youth": "Captain Tsubasa: World Youth",
    "catastrophic-necromancer": "Catastrophic Necromancer",
    "chichikogusa": "Chichikogusa",
    "chis-sweet-home": "Chi's Sweet Home",
    "chronicles-of-the-demon-faction": "Chronicles of the Demon Faction",
    "chronicles-of-the-lazy-sovereign": "Chronicles of the Lazy Sovereign",
    "classi9": "Classi9",
    "classmate": "Classmate",
    "code-geass-lelouch-of-the-rebellion": "Code Geass: Lelouch of the Rebellion",
    "code-geass-nightmare-of-nunnally": "Code Geass: Nightmare of Nunnally",
    "code-geass-suzaku-of-the-counterattack": "Code Geass: Suzaku of the Counterattack",
    "contract-admission": "Contract Admission",
    "convenience-store-worker-from-another-world": "Convenience Store Worker From Another World",
    "cosmic-heavenly-demon-3077": "Cosmic Heavenly Demon 3077",
    "cube-arts": "Cube Arts",
    "damn-demonic-swords": "Damn Demonic Swords",
    "dandadan": "Dandadan",
    "dandara-gohan": "Dandara Gohan",
    "dao-of-the-bizarre-immortal": "Dao of the Bizarre Immortal",
    "dear-anemone": "Dear Anemone",
    "death-note": "Death Note",
    "death-note-color-edition": "Death Note [Colored Edition]",
    "death-note-special-one-shot": "Death Note Special Oneshot",
    "detective-conan-hanzawa-the-criminal": "Detective Conan: Hanzawa the Criminal",
    "disappearance-diary": "Disappearance Diary",
    "dorohedoro": "Dorohedoro",
    "double-click": "Double Click",
    "douluo-dalu-3-the-legend-of-the-dragon-king": "Douluo Dalu III - The Legend of the Dragon King",
    "dr-stone-4d-science": "Dr. STONE: 4D Science",
    "dragon-ball": "Dragon Ball",
    "dragon-ball-episode-of-bardock": "Dragon Ball - Episode of Bardock",
    "dragon-ball-yardrats-the-story-of-a-survivor": "Dragon Ball - Yardrats, The Story of a Survivor",
    "dragon-prince-yuan": "Dragon Prince Yuan",
    "eat-and-go": "Eat and Go!",
    "eighty-six": "86—EIGHTY-SIX",
    "eleceed": "Eleceed",
    "emperor-of-solo-play": "Emperor of Solo Play",
    "escort-warrior": "Escort Warrior",
    "even-if-i-fall-into-a-horror-story-i-still-have-to-go-to-work": "Even if I fall into a ghost story, I still have to go to work",
    "evolution-begins-with-a-big-tree": "Evolution Begins With a Big Tree",
    "fate-prototype-sougin-no-fragments": "Fate/Prototype: Sougin no Fragments",
    "fate-samurai-remnant": "Fate/Samurai Remnant",
    "fate-type-redline": "Fate/type Redline",
    "fighting-girls": "Fighting Girls",
    "fog-land": "Fog Land",
    "for-your-murder": "For Your Murder",
    "forty-millenniums-of-cultivation": "Forty Millenniums of Cultivation",
    "frieren-beyond-journeys-end": "Frieren: Beyond Journey's End",
    "from-child-actor-to-world-star": "From Child Actor to World Star!",
    "from-useless-to-peerless-a-barrier-mages-journey": "From Useless to Peerless: A Barrier Mage's Journey",
    "frozen-hearts": "Frozen Hearts",
    "fullmetal-alchemist": "Fullmetal Alchemist",
    "gachiakuta": "Gachiakuta",
    "gakuen-babysitters": "Gakuen Babysitters",
    "gantz": "Gantz",
    "garouden": "Garouden",
    "genius-of-the-unique-lineage": "Genius of the Unique Lineage",
    "genius-prismatic-mage": "The Genius Prismatic Mage",
    "golden-kamuy": "Golden Kamuy",
    "gosu": "Gosu",
    "groundless": "GROUNDLESS",
    "haikyuu": "Haikyu!!",
    "haikyuu-bu": "Haikyu-bu!!",
    "hard-carry-support": "Hard Carry Support",
    "hells-paradise-jigokuraku": "Hell's Paradise: Jigokuraku",
    "hikari-no-iroha": "Hikari no Iroha",
    "home-at-the-horizon": "Home at the Horizon",
    "hoshizora-no-karasu": "Hoshizora no Karasu",
    "housekeeping": "Housekeeping",
    "hunter-age": "Hunter Age",
    "hunter-x-hunter": "Hunter x Hunter",
    "i-alone-am-an-ex-class-summoner": "I Alone Am an EX-Class Summoner",
    "i-became-the-berserker-of-the-world-i-created": "I Became the Berserker of the World I Created",
    "i-became-the-rogue-first-prince": "I Became The Rogue First Prince",
    "i-became-the-tyrant-of-a-defense-game": "I Became the Tyrant of a Defense Game",
    "ihoujin": "Ihoujin",
    "ikoku-nikki": "Ikoku Nikki",
    "im-going-to-destroy-this-country": "I'm Going to Destroy This Country",
    "im-gonna-annihilate-this-land": "I'm Gonna Annihilate This Land",
    "imouto-wa-siscon-ani-ga-mendokusai": "Imouto wa Siscon Ani ga Mendokusai",
    "infinite-level-up-in-murim": "Infinite Level Up in Murim",
    "inkling-alice": "Inkling Alice",
    "jaco-the-galactic-patrolman": "Jaco the Galactic Patrolman",
    "jiyujiyo": "Jiyujiyo",
    "jujutsu-kaisen": "Jujutsu Kaisen",
    "jujutsu-kaisen-0": "Jujutsu Kaisen 0",
    "kagurabachi": "Kagurabachi",
    "kaiju-no-8": "Kaiju No. 8",
    "kaiju-no-8-relax-ar": "Kaiju No. 8: Relax",
    "kaijuu-kamui": "Kaiju Kamui",
    "kaiten-no-albus": "Albus Changes the World",
    "kara-no-kyoukai-the-garden-of-sinners": "Kara no Kyoukai: the Garden of sinners",
    "kaya-chan-wa-kowakunai": "Kaya-chan Isn’t Scary",
    "keijis-kabuki-adventure": "Keiji's Kabuki Adventure",
    "kengan-omega": "Kengan Omega",
    "kill-the-hero": "Kill the Hero",
    "killing-guard": "Killing Guard",
    "killing-morph": "Killing Morph",
    "kimetsu-no-yaiba": "Demon Slayer: Kimetsu no Yaiba",
    "kimi-ga-kemono-ni-naru-mae-ni": "Kimi ga Kemono ni Naru Mae ni",
    "kimi-no-koe": "Kimi no Koe",
    "kimi-wa-yotsuba-no-clover": "You are a Four Leaf Clover",
    "king-of-apocalypse": "King of Apocalypse",
    "kingdom-hearts-358-2-days": "Kingdom Hearts 358/2 Days",
    "kiyora-tamayura": "Kiyora Tamayura",
    "legend-of-the-norther-blade": "Legend of the Northern Blade",
    "lemon-tree-forest": "Lemon Tree Forest",
    "level-999-goblin": "Level 999 Goblin",
    "light-of-the-dawn-remake": "Light of the Dawn (Remake)",
    "limit-breaker": "Limit Breaker",
    "limit-breaking-genius-mage": "Limit-Breaking Genius Mage",
    "love-thy-neighbou": "Love Thy Neighbour",
    "lunch-doki-wa-koishi-doki": "Lunch doki wa koishi doki",
    "madan-no-ichi": "Ichi the Witch",
    "made-in-abyss": "Made In Abyss",
    "magi-the-adventures-of-sinbad": "Magi: The Adventures Of Sinbad",
    "magic-academy-s-genius-blinker": "Magic Academy's Genius Blinker",
    "magic-emperor": "Magic Emperor",
    "mairimashita-iruma-kun-boku-doumei-no-game-michi": "Mairimashita! Iruma-kun: Boku Doumei no Game-michi",
    "marchen-crown": "Marchen Crown",
    "margraves-bastard-son-was-the-emperor": "Margrave's Bastard Son Was the Emperor",
    "martial-inheritance": "Martial Inheritance",
    "martial-peak": "Martial Peak",
    "mashle-magic-and-muscles": "Mashle: Magic and Muscles",
    "medalist": "Medalist",
    "medical-return": "Medical Return",
    "mercenary-enrollment": "Mercenary Enrollment",
    "midnight-rhapsody": "Midnight Rhapsody",
    "monster-eater": "Monster Eater",
    "moonlight-hair": "Moonlight Hair",
    "moonlight-sculptor-4-koma": "Moonlight Sculptor (4-Koma)",
    "munou-na-nana": "Munou na Nana",
    "murim-login": "Murim Login",
    "murims-youngest-miracle-demon-doctor": "Murim's Youngest Miracle Demon Doctor",
    "my-disciples-are-all-big-villains": "My Disciples Are All Big Villains",
    "my-disciples-are-all-invincible-monsters": "My Disciples are All Invincible Monsters",
    "my-exclusive-tower-guide": "My Exclusive Tower Guide",
    "my-hero-academia": "My Hero Academia",
    "my-pirate-prince": "My Pirate Prince",
    "naruto-digital-colored": "Naruto - Digital Colored Comics",
    "noblesse": "Noblesse",
    "old-newbie-kim-chunshik": "Old Newbie Kim Chun",
    "omniscient-readers-viewpoint": "Omniscient Reader's Viewpoint",
    "omoide-poro-poro": "Omoide Poro Poro",
    "omukae-shibuya": "Omukae Shibuya-kun",
    "one-operation-joker": "One Operation Joker",
    "one-piece-academy": "One Piece Academy",
    "one-piece-episode-a": "One Piece Episode A",
    "one-piece-straw-hat-theater": "One Piece: Straw Hat Theater",
    "one-piece-x-toriko": "One Piece x Toriko: Taste of the Devil Fruit",
    "one-punch-man": "One-Punch Man",
    "one-step-closer-to-the-demon-king": "One Step Closer to the Demon King",
    "ordinary-emperor": "Ordinary Emperor",
    "oshi-no-ko": "[Oshi no Ko]",
    "overgeared": "Overgeared",
    "overloard-of-insects": "Overlord of Insects",
    "overlord": "Overlord",
    "paradise-on-earth": "Paradise on Earth",
    "past-life-returner": "Past Life Returner",
    "peerless-dad": "Peerless Dad",
    "piano-forest": "Piano Forest",
    "pigpen": "PIGPEN",
    "planetes": "Planetes",
    "psycho-pass-kanshikan-kogami-shinya": "Psycho-Pass - Kanshikan Kougami Shinya",
    "raising-villains-the-right-way": "Raising Villains the Right Way",
    "ran-and-the-gray-world": "Ran and the Gray World",
    "rank-no-ura-soubi-musou": "The Unparalleled Hidden Rank Equipment",
    "ranking-of-kings": "Ranking of Kings",
    "rebirth-of-the-urban-immortal-emperor": "Rebirth of the Urban Immortal Emperor",
    "reborn-as-the-heavenly-martial-demon": "Reborn as the Heavenly Martial Demon",
    "red-hood": "Red Hood",
    "red-riding-hood": "Red Riding Hood",
    "red-shirt": "Red Shirt",
    "red-storm": "Red Storm",
    "regressing-with-the-kings-power": "Regressing with the King’s Power",
    "reincarnated-as-a-genius-prodigy-of-a-prestigious-family": "Reincarnated as a Genius Prodigy of a Prestigious Family",
    "reincarnation-of-the-fist-king": "Reincarnation of the Fist King",
    "reincarnators-stream": "Reincarnator’s Stream",
    "resurrection-boy": "Resurrection Boy",
    "return-of-the-frozen-player": "Return of the Frozen Player",
    "return-of-the-genius-swordmaster": "Return of The Genius Swordmaster",
    "return-of-the-high-ranking-civil-servant": "Return of the High-Ranking Civil Servant",
    "return-of-the-mount-hua-sect": "Return of the Mount Hua Sect",
    "return-of-the-runebound-professor": "Return of the Runebound Professor",
    "return-of-the-sss-class-ranker": "Return of the SSS-Class Ranker",
    "sakamoto-days": "Sakamoto Days",
    "sakamoto-holidays": "Sakamoto Holidays",
    "salon-diana": "Salon Diana",
    "seabird-and-the-wolf": "Seabird and the Wolf",
    "secret-family": "Secret Family",
    "secretly-more-powerful-than-the-hero": "Secretly More Powerful than the Hero",
    "seoul-station-barbarian": "Seoul Station Barbarian",
    "shadow-slave": "Shadow Slave",
    "shadows-house": "Shadows House × Kuro",
    "shamo": "Shamo",
    "sherlock-a-study-in-pink": "Sherlock: A Study in Pink",
    "shibuya-ninja": "Shibuya Ninja",
    "shihou-yuugi": "Shihou Yuugi",
    "shin-garouden": "Shin Garouden",
    "skeleton-soldier-couldnt-protect-the-dungeon": "Skeleton Soldier Couldn't Protect the Dungeon",
    "skeleton-warrior": "Skeleton Warrior",
    "slam-dunk": "Slam Dunk!",
    "smoking-behind-the-supermarket-with-you": "Smoking Behind the Supermarket with You",
    "snow-mountain-monster-princess": "Monster Princess of the Snowy Mountain",
    "solo-leveling": "Solo Leveling",
    "solo-leveling-ragnarok": "Solo Leveling: Ragnarok",
    "solo-max-level-newbie": "Solo Max-Level Newbie",
    "solo-strike-a-hundred-million-damage": "Solo Strike: A Hundred Million Damage",
    "soul-of-burning-steel": "Soul of Burning Steel",
    "special-civil-servant": "Special Civil Servant",
    "spoof-on-titan": "Spoof on Titan",
    "star-embracing-swordmaster": "The Stellar Swordmaster",
    "star-instructor-master-baek": "Star Instructor, Master Baek",
    "starting-from-today-ill-work-as-a-city-lord": "Starting From Today I'll Work as a City Lord",
    "study-group": "Study Group",
    "super-dragon-ball-heroes-meteor-mission": "Super Dragon Ball Heroes: Meteor Mission!",
    "surviving-the-apocalypse": "Surviving the Apocalypse",
    "suspicion-of-plagiarism": "Suspicion of Plagiarism",
    "sweet-home": "Sweet Home",
    "sword-devouring-swordmaster": "Sword Devouring Swordmaster",
    "sword-of-benevolence": "Sword of Benevolence",
    "swordmaster-s-youngest-son": "Swordmaster's Youngest Son",
    "terminally-ill-genius-dark-knight": "Terminally-Ill Genius Dark Knight",
    "terror-hunter": "Terror Hunter",
    "the-archmage-s-restaurant": "The Archmage's Restaurant",
    "the-back-alley-mage-s-return": "The Back Alley Mage's Second Life",
    "the-beginning-after-the-end": "The Beginning After the End",
    "the-beloved-gardener-of-the-world-tree": "The Beloved Gardener of the World Tree",
    "the-case-study-of-vanitas": "The Case Study of Vanitas",
    "the-cold-blooded-warrior": "The Cold-Blooded Warrior",
    "the-day-naruto-became-hokage": "The Day Naruto Became Hokage",
    "the-demon-king-overrun-by-heroes": "The Demon King Overrun by Heroes",
    "the-descent-of-the-demonic-master": "The Descent of the Demonic Master",
    "the-divine-demons-grand-ascension": "The Divine Demon’s Grand Ascension",
    "the-enigma-of-amigara-fault": "The Enigma of Amigara Fault",
    "the-fable-the-third-secret": "The Fable: The third secret",
    "the-final-boss-became-a-player": "The Final Boss Became a Player",
    "the-genius-martial-artist-who-remembers-everything": "The Martial Genius Who Remembers Everything",
    "the-genius-midfielder-s-passes-are-special": "The Genius Midfielder’s Passes are Special",
    "the-genius-spirited-streamer": "The Genius Spirited Streamer",
    "the-girl-from-the-other-side": "The Girl From the Other Side",
    "the-hero-returns": "The Hero Returns",
    "the-holy-power-of-modern-medicine": "The Holy Power of Modern Medicine",
    "the-horizon": "The Horizon",
    "the-house-without-time": "The House Without Time",
    "the-last-human": "The Last Human",
    "the-legendary-mechanic": "The Legendary Mechanic",
    "the-main-heroines-are-trying-to-kill-me": "The Main Heroines Are Trying to Kill Me",
    "the-marriage-of-the-unseen-duke": "The Marriage of the Unseen Duke",
    "the-max-level-hero-has-returned": "The Max Level Hero Has Returned!",
    "the-misfit-of-the-martial-world": "The Misfit of the Martial World",
    "the-new-beggars-sect": "The New Beggars' Sect",
    "the-player-that-cant-level-up": "The Player That Can’t Level Up",
    "the-rogue-10th-class-of-the-frontier-count": "The Rogue 10th-Class of the Frontier Count",
    "the-roguish-guard-in-a-medieval-fantasy": "The Roguish Guard in a Medieval Fantasy",
    "the-scholars-reincarnation": "The Scholar's Reincarnation",
    "the-silver-wheat-field": "The Silver Wheat Field",
    "the-skeleton-became-a-cat-dad": "The Skeleton Becomes a Cat Dad",
    "the-smiling-boxer": "The Smiling Boxer",
    "the-summer-hikaru-died": "The Summer Hikaru Died",
    "the-tang-clan-chronicles": "The Tang Clan Chronicles",
    "the-third-prince-of-the-fallen-kingdom-has-regress": "The Third Prince of the Fallen Kingdom Has Regressed",
    "the-tutorial-is-too-hard": "The Tutorial Is Too Hard",
    "the-worlds-best-kunlun-tavern": "The World's Best Kunlun Tavern",
    "the-worlds-best-martial-arts-instructor": "The World's Best Martial Arts Instructor",
    "the-youngest-son-of-the-eunhae-merchant-group": "The Youngest Son of the Eunhae Merchant Group",
    "the-zenith": "The Zenith",
    "third-rate-martial-family-becomes-the-best-under-heaven": "Third-Rate Martial Family Becomes the Best Under Heaven",
    "this-martial-saint-is-way-too-generous": "This Martial Saint Is Way Too Generous",
    "to-hell-with-the-status-window": "To Hell With the Status Window",
    "toilet-bound-hanako-kun": "Toilet-Bound Hanako-kun",
    "tokyo-ghoul": "TOKYO GHOUL",
    "tokyo-ghoul-re": "Tokyo Ghoul: re",
    "tomie": "Tomie",
    "tomodachi-game": "Tomodachi Game",
    "tonari-no-kaibutsu-kun": "Tonari no Kaibutsu-kun",
    "top-1-fighting-tutoring": "Top 1 Fighting Tutoring",
    "top-tier-providence-secretly-cultivate-for-a-thousand-years": "Top Tier Providence: Secretly Cultivate for a Thousand Years",
    "tower-of-god-urek-mazino": "Tower of God: Urek Mazino",
    "trait-hoarder": "Trait Hoarder",
    "true-beauty": "True Beauty",
    "true-martial-world": "A True Martial World",
    "uchiha-sasuke-no-sharingan-den": "Naruto: Chibi Sasuke's Sharingan Legend",
    "ultimate-exorcist-kiyoshi": "Ultimate Exorcist Kiyoshi",
    "unordinary": "unOrdinary",
    "urareta-henkyou-haku-reijou-wa-ringoku-no-outaishi-ni-dekiai-sareru": "Urareta Henkyou Haku Reijou wa Ringoku no Outaishi ni Dekiai Sareru",
    "uratarou": "Uratarou",
    "vagabond": "Vagabond",
    "versus": "Versus",
    "villain-is-here": "Villain Is Here",
    "villain-to-kill": "Villain to Kill",
    "volcanic-age": "Volcanic Age",
    "weak-hero": "Weak Hero",
    "wee": "WEE",
    "what-a-bountiful-harvest-demon-lord": "What a Bountiful Harvest, Demon Lord!",
    "whats-our-hero-doing": "What's Our Hero Doing?",
    "wild-west-murim": "Wild West Murim",
    "wind-breaker": "WIND BREAKER",
    "wistorias-wand-and-sword": "Wistoria: Wand and Sword",
    "witchriv": "WITCHRIV",
    "with-you-through-the-window": "With You Through the Window",
    "world-saving-is-a-skill": "World-Saving Is a Skill",
    "worlds-strongest-troll": "World's Strongest Troll",
    "writers-legacy": "Writers Legacy",
    "yong-heng-zhi-zun": "Yong Heng Zhi Zun",
    "yoru-no-manimani": "Our Aimless Nights",
    "yuan-long": "Yuan Long",
    "yuan-zun": "Dragon Prince Yuan",
    "zombie-fight": "Zombie Fight"
};
const ARABIC_RE = /[\u0600-\u06ff]/;
const titles = mangaTimeEnglishTitles;
function sourceEnglishTitle(item) {
    if (item.source !== "mangatime" || !ARABIC_RE.test(item.title)) return "";
    return String(titles[item.slug] ?? "").trim();
}
function sourceDisplayTitle(item) {
    const english = sourceEnglishTitle(item);
    return english ? `${item.title} (${english})` : item.title;
}

return {sourceEnglishTitle};
})();
const {RECOMMENDATION_ALGORITHM_VERSION,RECOMMENDATION_CACHE_TTL_MS,RECOMMENDATION_WEIGHTS} = (()=>{
const RECOMMENDATION_ALGORITHM_VERSION = "10.5.2";
const RECOMMENDATION_CACHE_TTL_MS = 30 * 60 * 1000;
const RECOMMENDATION_WEIGHTS = {
    favorite: 6,
    completed: 5,
    reading: 3,
    list: 2.5,
    planned: 1,
    paused: -1,
    shallowRead: 0.5,
    deepReadMax: 3,
    recentSevenDays: 1.5,
    recentThirtyDays: 1,
    recentNinetyDays: 0.5,
    perWorkCap: 9,
    tasteSimilarity: 7,
    seedSimilarity: 3,
    popularityTieBreaker: 0.25,
    freshnessTieBreaker: 0.15,
    typeFeatureWeight: 0.45,
    minimumConfidence: 0.14,
    diversityPenalty: 0.7
};
const FYP_INITIAL_COUNT = 20;
const FYP_LOAD_MORE_COUNT = 12;

return {RECOMMENDATION_ALGORITHM_VERSION,RECOMMENDATION_CACHE_TTL_MS,RECOMMENDATION_WEIGHTS};
})();
const W = RECOMMENDATION_WEIGHTS;
const {mergeSourceItems,preferredSourceCover} = (()=>{
const SOURCE_PRIORITY = {
    mangatime: 0,
    teamx: 1,
    "3asq": 2,
    starzmanga: 3,
    xsano: 4,
    mangalik: 5,
    azora: 6
};
const COVER_PRIORITY = {
    teamx: 0,
    "3asq": 1,
    starzmanga: 2,
    xsano: 3,
    mangalik: 4,
    azora: 5,
    mangatime: 5
};
const LATIN_ARTICLES = new Set([
    "the",
    "a",
    "an"
]);
const GENERIC_TITLE_SUFFIXES = new Set([
    "manga",
    "manhwa",
    "manhua",
    "webtoon",
    "comic"
]);
function normalizeSourceIdentity(value) {
    return String(value ?? "").normalize("NFKD").replace(/[\u0300-\u036f]/g, "").toLowerCase().replace(/ـ/g, "").replace(/[أإآ]/g, "ا").replace(/ة/g, "ه").replace(/ى/g, "ي").replace(/ؤ/g, "و").replace(/ئ/g, "ي").replace(/&/g, " and ").replace(/[’‘`´]/g, "'").replace(/[^a-z0-9\u0600-\u06ff]+/g, " ").replace(/\s+/g, " ").trim();
}
function identityTokens(value) {
    const tokens = normalizeSourceIdentity(value).split(" ").filter(Boolean);
    const latinOnly = tokens.every((token)=>/^[a-z0-9]+$/.test(token));
    if (!latinOnly) return tokens;
    const cleaned = [
        ...tokens
    ];
    while(cleaned.length > 1 && LATIN_ARTICLES.has(cleaned[0]))cleaned.shift();
    return cleaned.filter((token)=>token !== "s");
}
function isUsefulIdentity(value) {
    if (value.length < 5) return false;
    const words = value.split(" ").filter(Boolean);
    return words.length >= 2 || value.length >= 7;
}
function addIdentity(set, raw) {
    const normalized = normalizeSourceIdentity(raw);
    if (!isUsefulIdentity(normalized)) return;
    set.add(normalized);
    const tokens = identityTokens(normalized);
    if (tokens.length) {
        const withoutArticles = tokens.join(" ");
        if (withoutArticles !== normalized && isUsefulIdentity(withoutArticles)) {
            set.add(withoutArticles);
        }
        if (tokens.length > 1 && GENERIC_TITLE_SUFFIXES.has(tokens[tokens.length - 1])) {
            const withoutSuffix = tokens.slice(0, -1).join(" ");
            if (isUsefulIdentity(withoutSuffix)) set.add(withoutSuffix);
        }
        if (tokens.length > 1) {
            const tokenSignature = [
                ...tokens
            ].sort().join(" ");
            if (tokenSignature !== normalized && isUsefulIdentity(tokenSignature)) {
                set.add(tokenSignature);
            }
        }
    }
}
function titleWithoutTrailingQualifier(value) {
    return String(value ?? "").replace(/\s*[\[(][^\])]+[\])]\s*$/, "").trim();
}
function sourceIdentityCandidates(item) {
    const identities = new Set();
    const english = sourceEnglishTitle(item);
    if (english) addIdentity(identities, english);
    const plainTitle = titleWithoutTrailingQualifier(item.title);
    addIdentity(identities, item.title);
    if (plainTitle && plainTitle !== item.title) addIdentity(identities, plainTitle);
    addIdentity(identities, item.slug.replace(/[-_]+/g, " "));
    return identities;
}
function intersects(a, b) {
    for (const value of a){
        if (b.has(value)) return true;
    }
    return false;
}
function numericSignature(value) {
    return normalizeSourceIdentity(value).match(/\d+(?:\.\d+)?/g)?.join("|") ?? "";
}
function levenshteinDistance(a, b) {
    if (a === b) return 0;
    if (!a.length) return b.length;
    if (!b.length) return a.length;
    const previous = Array.from({
        length: b.length + 1
    }, (_, index)=>index);
    const current = new Array(b.length + 1);
    for(let i = 1; i <= a.length; i += 1){
        current[0] = i;
        for(let j = 1; j <= b.length; j += 1){
            current[j] = Math.min(current[j - 1] + 1, previous[j] + 1, previous[j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1));
        }
        for(let j = 0; j <= b.length; j += 1)previous[j] = current[j];
    }
    return previous[b.length];
}
function tokenSimilarity(a, b) {
    const left = new Set(identityTokens(a));
    const right = new Set(identityTokens(b));
    if (!left.size || !right.size) return 0;
    let common = 0;
    for (const token of left){
        if (right.has(token)) common += 1;
    }
    const union = new Set([
        ...left,
        ...right
    ]).size;
    return union ? common / union : 0;
}
function identitiesLikelySame(a, b) {
    if (a === b) return true;
    const aNumbers = numericSignature(a);
    const bNumbers = numericSignature(b);
    if ((aNumbers || bNumbers) && aNumbers !== bNumbers) return false;
    const aTokens = identityTokens(a);
    const bTokens = identityTokens(b);
    if (!aTokens.length || !bTokens.length) return false;
    const aSignature = [
        ...aTokens
    ].sort().join(" ");
    const bSignature = [
        ...bTokens
    ].sort().join(" ");
    if (aSignature === bSignature && isUsefulIdentity(aSignature)) return true;
    const compactA = aTokens.join("");
    const compactB = bTokens.join("");
    const maxLength = Math.max(compactA.length, compactB.length);
    const minLength = Math.min(compactA.length, compactB.length);
    if (minLength >= 10 && maxLength - minLength <= Math.max(2, Math.floor(maxLength * 0.08))) {
        const maxDistance = Math.max(1, Math.floor(maxLength * 0.08));
        if (levenshteinDistance(compactA, compactB) <= maxDistance) return true;
    }
    if (aTokens.length >= 3 && bTokens.length >= 3 && minLength / maxLength >= 0.82 && tokenSimilarity(a, b) >= 0.86) {
        return true;
    }
    return false;
}
function itemsLikelySame(a, b, aIdentities, bIdentities) {
    if (a.source === b.source) return false;
    if (intersects(aIdentities, bIdentities)) return true;
    for (const left of aIdentities){
        for (const right of bIdentities){
            if (identitiesLikelySame(left, right)) return true;
        }
    }
    return false;
}
function pickPrimary(items) {
    return [
        ...items
    ].sort((a, b)=>{
        const sourceOrder = (SOURCE_PRIORITY[a.source] ?? 99) - (SOURCE_PRIORITY[b.source] ?? 99);
        if (sourceOrder) return sourceOrder;
        if (Boolean(a.cover) !== Boolean(b.cover)) return a.cover ? -1 : 1;
        return a.key.localeCompare(b.key);
    })[0];
}
function preferredSourceCover(items) {
    const candidates = items.filter((item)=>Boolean(item.cover));
    if (!candidates.length) return items[0];
    return [
        ...candidates
    ].sort((a, b)=>{
        const sourceOrder = (COVER_PRIORITY[a.source] ?? 99) - (COVER_PRIORITY[b.source] ?? 99);
        if (sourceOrder) return sourceOrder;
        return a.key.localeCompare(b.key);
    })[0];
}
function mergeSourceItems(items) {
    const uniqueItems = [
        ...new Map(items.map((item)=>[
                item.key,
                item
            ])).values()
    ];
    if (!uniqueItems.length) return [];
    const identities = uniqueItems.map(sourceIdentityCandidates);
    const parents = uniqueItems.map((_, index)=>index);
    const componentSources = uniqueItems.map((item)=>new Set([
            item.source
        ]));
    const find = (index)=>{
        let root = index;
        while(parents[root] !== root)root = parents[root];
        while(parents[index] !== index){
            const next = parents[index];
            parents[index] = root;
            index = next;
        }
        return root;
    };
    const union = (leftIndex, rightIndex)=>{
        const leftRoot = find(leftIndex);
        const rightRoot = find(rightIndex);
        if (leftRoot === rightRoot) return;
        const leftSources = componentSources[leftRoot];
        const rightSources = componentSources[rightRoot];
        for (const source of leftSources){
            if (rightSources.has(source)) return;
        }
        parents[rightRoot] = leftRoot;
        for (const source of rightSources)leftSources.add(source);
    };
    for(let left = 0; left < uniqueItems.length; left += 1){
        for(let right = left + 1; right < uniqueItems.length; right += 1){
            if (itemsLikelySame(uniqueItems[left], uniqueItems[right], identities[left], identities[right])) {
                union(left, right);
            }
        }
    }
    const grouped = new Map();
    uniqueItems.forEach((item, index)=>{
        const root = find(index);
        const existing = grouped.get(root);
        if (existing) {
            existing.items.push(item);
            existing.firstIndex = Math.min(existing.firstIndex, index);
        } else {
            grouped.set(root, {
                firstIndex: index,
                items: [
                    item
                ]
            });
        }
    });
    return [
        ...grouped.values()
    ].sort((a, b)=>a.firstIndex - b.firstIndex).map(({ items: groupedItems })=>({
            id: groupedItems.map((entry)=>entry.key).sort().join("|"),
            primary: pickPrimary(groupedItems),
            items: groupedItems
        }));
}
function queryScoreForItem(item, query) {
    const needle = normalizeSourceIdentity(query);
    if (!needle) return 1000;
    const title = normalizeSourceIdentity(item.title);
    const english = normalizeSourceIdentity(sourceEnglishTitle(item));
    const slug = normalizeSourceIdentity(item.slug.replace(/[-_]+/g, " "));
    const candidates = [
        ...new Set([
            title,
            english,
            slug
        ].filter(Boolean))
    ];
    if (candidates.some((value)=>value === needle)) return 0;
    const queryTokens = identityTokens(needle);
    const querySignature = [
        ...queryTokens
    ].sort().join(" ");
    if (querySignature && candidates.some((value)=>[
            ...identityTokens(value)
        ].sort().join(" ") === querySignature)) {
        return 1;
    }
    if (candidates.some((value)=>value.startsWith(needle + " "))) return 10;
    if (candidates.some((value)=>value.includes(needle))) return 20;
    if (queryTokens.length && candidates.some((value)=>{
        const tokens = new Set(identityTokens(value));
        return queryTokens.every((token)=>tokens.has(token));
    })) {
        return 30;
    }
    let bestOverlap = 0;
    for (const value of candidates){
        bestOverlap = Math.max(bestOverlap, tokenSimilarity(needle, value));
    }
    if (bestOverlap > 0) return 50 - bestOverlap * 10;
    return 100;
}
function rankSourceGroupsByQuery(groups, query) {
    if (!query.trim()) return groups;
    return groups.map((group, index)=>({
            group,
            index,
            score: Math.min(...group.items.map((item)=>queryScoreForItem(item, query)))
        })).sort((a, b)=>a.score - b.score || a.index - b.index).map(({ group })=>group);
}
function sourceGroupKeys(values) {
    return [
        ...new Set(values.map((value)=>typeof value === "string" ? value : value.key).filter(isSourceKey))
    ];
}
function parseSourceGroupKeys(raw, currentKey) {
    const values = String(raw ?? "").split(",").map((value)=>value.trim()).filter(Boolean).slice(0, 12);
    return sourceGroupKeys([
        currentKey,
        ...values
    ]);
}
function sourceDetailsPath(key, values = []) {
    const keys = sourceGroupKeys([
        key,
        ...values
    ]);
    const base = `/source/${encodeURIComponent(key)}`;
    if (keys.length <= 1) return base;
    const search = new URLSearchParams({
        sources: keys.join(",")
    });
    return `${base}?${search.toString()}`;
}
function isSourceKey(value) {
    return /^(?:mt|tx|aq|sz|xs|ml|az):[A-Za-z0-9_-]{1,110}$/.test(value);
}

return {mergeSourceItems,preferredSourceCover};
})();
const {rankRecommendations} = (()=>{
function normalizedLabel(value) {
    return String(value ?? "").trim().replace(/\s+/g, " ").toLowerCase();
}
function vectorFor(item) {
    const vector = new Map();
    const genres = [
        ...new Set((item.genres ?? []).map(normalizedLabel).filter(Boolean))
    ];
    for (const genre of genres)vector.set(`genre:${genre}`, 1);
    const type = normalizedLabel(item.type);
    if (type) vector.set(`type:${type}`, W.typeFeatureWeight);
    return normalizeVector(vector);
}
function normalizeVector(vector) {
    const norm = Math.sqrt([
        ...vector.values()
    ].reduce((sum, value)=>sum + value * value, 0));
    if (!norm) return vector;
    return new Map([
        ...vector.entries()
    ].map(([key, value])=>[
            key,
            value / norm
        ]));
}
function cosine(left, right) {
    if (!left.size || !right.size) return 0;
    let score = 0;
    for (const [key, value] of left)score += value * (right.get(key) ?? 0);
    return Math.max(0, Math.min(1, score));
}
function tasteVector(signals) {
    const out = new Map();
    for (const signal of signals){
        const contribution = Math.max(0, Math.min(W.perWorkCap, signal.weight));
        if (contribution <= 0) continue;
        for (const [key, value] of vectorFor(signal.item)){
            out.set(key, (out.get(key) ?? 0) + value * contribution);
        }
    }
    return normalizeVector(out);
}
function metadataConfidence(item) {
    const genreCount = [
        ...new Set((item.genres ?? []).map(normalizedLabel).filter(Boolean))
    ].length;
    if (genreCount >= 3) return 1;
    if (genreCount === 2) return 0.9;
    if (genreCount === 1) return 0.78;
    return item.type ? 0.55 : 0;
}
function reasonFor(candidate, signals) {
    const candidateVector = vectorFor(candidate);
    const scored = signals.filter((signal)=>signal.weight > 0).map((signal)=>({
            signal,
            similarity: cosine(candidateVector, vectorFor(signal.item))
        })).sort((a, b)=>{
        const scoreDiff = b.similarity * b.signal.weight - a.similarity * a.signal.weight;
        return scoreDiff || a.signal.item.key.localeCompare(b.signal.item.key);
    });
    const best = scored[0];
    if (!best || best.similarity < 0.16) {
        const labels = (candidate.genres ?? []).filter(Boolean).slice(0, 2);
        return labels.length ? `متوافق مع اهتماماتك في ${labels.join(" و")}` : "متوافق مع نمط قراءتك";
    }
    const title = best.signal.item.title;
    if (best.signal.kind === "favorite") return `مشابه لـ ${title} الموجود في مفضلتك`;
    if (best.signal.kind === "completed") return `مشابه لقصة أكملتها: ${title}`;
    if (best.signal.kind === "reading" || best.signal.kind === "history") {
        return `لأنك تقرأ ${title}`;
    }
    if (best.signal.kind === "list") return `قريب من قصص قوائمك مثل ${title}`;
    return `قريب من ${title} الذي حفظته للقراءة`;
}
function rankBase(candidate, taste, signals) {
    const vector = vectorFor(candidate.item);
    const confidence = cosine(vector, taste) * metadataConfidence(candidate.item);
    let strongestSeed = 0;
    for (const signal of signals){
        if (signal.weight <= 0) continue;
        const similarity = cosine(vector, vectorFor(signal.item));
        strongestSeed = Math.max(strongestSeed, similarity * Math.min(1, signal.weight / W.perWorkCap));
    }
    const score = confidence * W.tasteSimilarity + strongestSeed * W.seedSimilarity + candidate.popularity * W.popularityTieBreaker + candidate.freshness * W.freshnessTieBreaker;
    return {
        score,
        confidence,
        vector
    };
}
function diversify(ranked) {
    const remaining = [
        ...ranked
    ];
    const selected = [];
    while(remaining.length){
        let bestIndex = 0;
        let bestAdjusted = Number.NEGATIVE_INFINITY;
        for(let index = 0; index < remaining.length; index += 1){
            const current = remaining[index];
            const maxSimilarity = selected.reduce((max, picked)=>Math.max(max, cosine(current.vector, picked.vector)), 0);
            const adjusted = current.score * (1 - maxSimilarity * W.diversityPenalty);
            const best = remaining[bestIndex];
            if (adjusted > bestAdjusted || adjusted === bestAdjusted && current.item.key.localeCompare(best.item.key) < 0) {
                bestAdjusted = adjusted;
                bestIndex = index;
            }
        }
        selected.push(remaining.splice(bestIndex, 1)[0]);
    }
    return selected.map(({ vector: _vector, ...recommendation })=>recommendation);
}
function rankRecommendations(candidates, signals) {
    const taste = tasteVector(signals);
    const personalized = taste.size > 0;
    if (!personalized) {
        return [
            ...candidates
        ].sort((a, b)=>b.popularity - a.popularity || b.freshness - a.freshness || a.item.key.localeCompare(b.item.key)).map((candidate)=>({
                ...candidate,
                score: candidate.popularity + candidate.freshness * 0.25,
                confidence: 0,
                reason: "قصة متاحة للقراءة الآن",
                algorithmVersion: RECOMMENDATION_ALGORITHM_VERSION
            }));
    }
    const ranked = candidates.map((candidate)=>{
        const base = rankBase(candidate, taste, signals);
        return {
            ...candidate,
            score: base.score,
            confidence: base.confidence,
            vector: base.vector,
            reason: reasonFor(candidate.item, signals),
            algorithmVersion: RECOMMENDATION_ALGORITHM_VERSION
        };
    }).filter((candidate)=>candidate.confidence >= W.minimumConfidence).sort((a, b)=>b.score - a.score || b.confidence - a.confidence || a.item.key.localeCompare(b.item.key));
    return diversify(ranked);
}
function recommendationFeatureSignature(item) {
    return [
        ...vectorFor(item).keys()
    ].sort().join("|");
}

return {rankRecommendations};
})();
const fypEngine = (()=>{
const SOURCES = [
    "mangatime",
    "teamx",
    "3asq",
    "starzmanga",
    "xsano",
    "mangalik"
];
async function mapWithConcurrency(values, concurrency, mapper) {
    const results = new Array(values.length);
    let cursor = 0;
    const workers = Array.from({
        length: Math.min(concurrency, values.length)
    }, async ()=>{
        while(true){
            const index = cursor++;
            if (index >= values.length) break;
            results[index] = await mapper(values[index], index);
        }
    });
    await Promise.all(workers);
    return results;
}
async function resolveInChunks(keys, onProgress) {
    const unique = [
        ...new Set(keys)
    ].filter(sourceService.isSourceKey);
    const chunks = [];
    for(let index = 0; index < unique.length; index += 60){
        chunks.push(unique.slice(index, index + 60));
    }
    let completed = 0;
    const settled = await Promise.allSettled(chunks.map((chunk)=>sourceService.resolve(chunk).finally(()=>{
            completed += 1;
            onProgress?.(completed, chunks.length);
        })));
    return settled.flatMap((result)=>result.status === "fulfilled" ? result.value : []);
}
function signalKind(key, entry, favorite, listKeys, reading) {
    if (favorite.has(key)) return "favorite";
    if (entry?.status === "completed") return "completed";
    if (entry?.status === "reading") return "reading";
    if (listKeys.has(key)) return "list";
    if (entry?.status === "planned") return "planned";
    return reading ? "history" : "planned";
}
function signalWeight(key, item, entry, favorite, listKeys, reading, now) {
    let weight = 0;
    if (favorite.has(key)) weight += W.favorite;
    if (entry?.status === "completed") weight += W.completed;
    if (entry?.status === "reading") weight += W.reading;
    if (entry?.status === "planned") weight += W.planned;
    if (entry?.status === "paused") weight += W.paused;
    if (listKeys.has(key)) weight += W.list;
    if (reading) {
        const maxChapter = item.latest ?? Math.max(0, ...(item.chapters ?? []).map((chapter)=>Number(chapter.number)).filter(Number.isFinite));
        if (maxChapter > 0 && reading.highestChapter != null) {
            const progress = Math.max(0, Math.min(1, reading.highestChapter / maxChapter));
            weight += progress > 0 ? W.shallowRead + progress * W.deepReadMax : 0;
        } else if (reading.readCount > 0) {
            weight += Math.min(1.5, W.shallowRead + reading.readCount / 20);
        }
        if (reading.lastReadAt != null) {
            const age = now - reading.lastReadAt;
            if (age <= 7 * 86_400_000) weight += W.recentSevenDays;
            else if (age <= 30 * 86_400_000) weight += W.recentThirtyDays;
            else if (age <= 90 * 86_400_000) weight += W.recentNinetyDays;
        }
    }
    return Math.max(-W.perWorkCap, Math.min(W.perWorkCap, weight));
}
function snapshotKey(userId) {
    return "wany:fyp:" + userId + ":" + RECOMMENDATION_ALGORITHM_VERSION;
}
function readSnapshot(userId, signature) {
    try {
        const raw = sessionStorage.getItem(snapshotKey(userId));
        if (!raw) return null;
        const parsed = JSON.parse(raw);
        if (parsed.algorithmVersion !== RECOMMENDATION_ALGORITHM_VERSION || parsed.tasteSignature !== signature || Date.now() - parsed.generatedAt > RECOMMENDATION_CACHE_TTL_MS) {
            return null;
        }
        return parsed;
    } catch  {
        return null;
    }
}
function writeSnapshot(userId, snapshot) {
    try {
        sessionStorage.setItem(snapshotKey(userId), JSON.stringify(snapshot));
    } catch  {}
}
async function loadLists(onProgress) {
    const summaries = await userDataService.getLists();
    let completed = 0;
    const settled = await Promise.allSettled(summaries.map((summary)=>userDataService.getList(summary.id).finally(()=>{
            completed += 1;
            onProgress?.(completed, summaries.length);
        })));
    onProgress?.(summaries.length, summaries.length);
    return settled.flatMap((result)=>result.status === "fulfilled" ? [
            result.value
        ] : []);
}
function buildTasteSignature(data, state, lists) {
    const favorite = [
        ...data.favorites
    ].sort().join(",");
    const library = [
        ...data.library
    ].sort((a, b)=>a.mangaId.localeCompare(b.mangaId)).map((entry)=>entry.mangaId + ":" + entry.status + ":" + (entry.highestReachedChapter ?? "")).join(",");
    const listItems = lists.flatMap((list)=>list.items.map((item)=>item.mangaId)).sort().join(",");
    const reading = [
        ...state.readingWorks
    ].sort((a, b)=>a.mangaId.localeCompare(b.mangaId)).map((entry)=>entry.mangaId + ":" + entry.readCount + ":" + (entry.highestChapter ?? "")).join(",");
    return [
        favorite,
        library,
        listItems,
        reading
    ].join("|");
}
async function hydrateSignalItems(items, onProgress) {
    let completed = 0;
    return mapWithConcurrency(items, 6, async (item)=>{
        try {
            return await sourceService.getSeries(item.key);
        } catch  {
            return item;
        } finally{
            completed += 1;
            onProgress?.(completed, items.length);
        }
    });
}
async function hydrateCandidate(group) {
    const ordered = [
        group.primary,
        ...group.items.filter((item)=>item.key !== group.primary.key)
    ];
    let best = null;
    for (const item of ordered.slice(0, 3)){
        try {
            const detail = await sourceService.getSeries(item.key);
            if ((detail.chapters?.length ?? 0) > 0) {
                best = detail;
                break;
            }
            best ??= detail;
        } catch  {}
    }
    if (!best || !(best.chapters?.length ?? 0)) return null;
    const cover = preferredSourceCover([
        best,
        ...group.items
    ]) ?? best;
    if (!cover.cover) return null;
    return {
        item: {
            ...best,
            cover: cover.cover,
            chapters: undefined
        },
        sourceKeys: group.items.map((item)=>item.key)
    };
}
async function buildFyp(data, userId, onProgress) {
    let lastReported = 0;
    const report = (percent)=>{
        const next = Math.max(1, Math.min(100, Math.round(percent * 10) / 10));
        if (next > lastReported) {
            lastReported = next;
            onProgress?.(next);
        }
    };
    report(1);
    const [state, lists] = await Promise.all([
        userDataService.getPersonalizationState().then((value)=>{
            report(8);
            return value;
        }),
        loadLists((completed, total)=>report(8 + completed / Math.max(1, total) * 12))
    ]);
    report(20);
    const signature = buildTasteSignature(data, state, lists);
    const cached = readSnapshot(userId, signature);
    if (cached) {
        report(100);
        return cached;
    }
    const favorite = new Set(data.favorites);
    const listKeys = new Set(lists.flatMap((list)=>list.items.map((item)=>item.mangaId)));
    const libraryByKey = new Map(data.library.map((entry)=>[
            entry.mangaId,
            entry
        ]));
    const readingByKey = new Map(state.readingWorks.map((entry)=>[
            entry.mangaId,
            entry
        ]));
    const knownKeys = new Set([
        ...favorite,
        ...listKeys,
        ...libraryByKey.keys(),
        ...readingByKey.keys()
    ]);
    const knownBase = await resolveInChunks([
        ...knownKeys
    ], (completed, total)=>report(20 + completed / Math.max(1, total) * 12));
    report(32);
    const priority = [
        ...knownBase
    ].sort((a, b)=>{
        const wa = (favorite.has(a.key) ? W.favorite : 0) + (libraryByKey.get(a.key)?.status === "completed" ? W.completed : 0) + (readingByKey.get(a.key)?.lastReadAt ?? 0) / 1e14;
        const wb = (favorite.has(b.key) ? W.favorite : 0) + (libraryByKey.get(b.key)?.status === "completed" ? W.completed : 0) + (readingByKey.get(b.key)?.lastReadAt ?? 0) / 1e14;
        return wb - wa || a.key.localeCompare(b.key);
    });
    const signalItems = await hydrateSignalItems(priority.slice(0, 48), (completed, total)=>report(32 + completed / Math.max(1, total) * 16));
    report(48);
    const now = Date.now();
    const signals = signalItems.flatMap((item)=>{
        const entry = libraryByKey.get(item.key);
        const reading = readingByKey.get(item.key);
        const weight = signalWeight(item.key, item, entry, favorite, listKeys, reading, now);
        if (weight <= 0) return [];
        return [
            {
                item,
                weight,
                kind: signalKind(item.key, entry, favorite, listKeys, reading),
                lastReadAt: reading?.lastReadAt ?? null
            }
        ];
    });
    const sourceRequestTotal = SOURCES.length * 2;
    let completedSourceRequests = 0;
    const trackSourceRequest = (request)=>request.finally(()=>{
            completedSourceRequests += 1;
            report(48 + completedSourceRequests / sourceRequestTotal * 25);
        });
    const sourcePairs = await Promise.allSettled(SOURCES.flatMap((source)=>[
            trackSourceRequest(sourceService.latest(source, 1).then((result)=>({
                    mode: "latest",
                    result
                }))),
            trackSourceRequest(sourceService.popular(source, 1).then((result)=>({
                    mode: "popular",
                    result
                })))
        ]));
    const items = [];
    const popularity = new Map();
    const freshness = new Map();
    for (const settled of sourcePairs){
        if (settled.status !== "fulfilled") continue;
        const { mode, result } = settled.value;
        result.items.forEach((item, index)=>{
            items.push(item);
            const value = Math.max(0, 1 - index / Math.max(1, result.items.length));
            const map = mode === "popular" ? popularity : freshness;
            map.set(item.key, Math.max(map.get(item.key) ?? 0, value));
        });
    }
    const merged = mergeSourceItems([
        ...knownBase,
        ...items
    ]);
    const candidateGroups = merged.filter((group)=>!group.items.some((item)=>knownKeys.has(item.key))).map((group)=>({
            group,
            popularity: Math.max(...group.items.map((item)=>popularity.get(item.key) ?? 0), 0),
            freshness: Math.max(...group.items.map((item)=>freshness.get(item.key) ?? 0), 0)
        })).sort((a, b)=>b.popularity + b.freshness - (a.popularity + a.freshness) || a.group.id.localeCompare(b.group.id)).slice(0, 72);
    let hydratedCandidates = 0;
    const hydrated = await mapWithConcurrency(candidateGroups, 6, async (candidate)=>{
        try {
            const work = await hydrateCandidate(candidate.group);
            if (!work) return null;
            return {
                ...work,
                popularity: candidate.popularity,
                freshness: candidate.freshness
            };
        } finally{
            hydratedCandidates += 1;
            report(73 + hydratedCandidates / Math.max(1, candidateGroups.length) * 25);
        }
    });
    report(98);
    const candidates = hydrated.filter((candidate)=>candidate !== null);
    const recommendations = rankRecommendations(candidates, signals);
    const snapshot = {
        generatedAt: Date.now(),
        algorithmVersion: RECOMMENDATION_ALGORITHM_VERSION,
        tasteSignature: signature,
        coldStart: signals.length === 0,
        recommendations
    };
    writeSnapshot(userId, snapshot);
    report(100);
    return snapshot;
}

return {buildFyp};
})();
const newEngine = (()=>{
const VERIFIED_NEW_FEED_SOURCES = [
    "3asq",
    "teamx",
    "mangalik",
    "mangatime",
    "xsano",
    "starzmanga",
    "azora"
];
const SOURCE_LABELS = {
    mangatime: "MangaTime",
    teamx: "TeamX",
    "3asq": "3asq",
    starzmanga: "StarzManga",
    xsano: "XSano",
    mangalik: "MangaLik",
    azora: "Azora"
};
const NEW_CHAPTER_WINDOW_MS = 24 * 60 * 60_000;
const MAX_NEW_CHAPTERS_PER_WORK = 5;
const VERIFIED_SOURCE_SCAN_PAGES = {
    "3asq": 2,
    teamx: 1,
    mangalik: 1,
    mangatime: 1,
    xsano: 1,
    starzmanga: 1,
    azora: 1
};
function parsePublished(value) {
    if (!value) return null;
    const timestamp = Date.parse(value);
    return Number.isFinite(timestamp) ? timestamp : null;
}
function releaseFor(chapter) {
    const published = parsePublished(chapter.publishedAt);
    return published == null ? null : {
        timestamp: published,
        kind: "published"
    };
}
function readKey(mangaId, chapter) {
    return `${mangaId}:${chapter}`;
}
function exactChapterIdentity(chapter) {
    const number = Number(chapter.number);
    return Number.isFinite(number) ? String(number) : chapter.title.trim();
}
const NEW_SOURCE_BUDGET_MS = {
    mangatime: 20_000,
    starzmanga: 15_000,
    mangalik: 15_000,
    xsano: 20_000,
    azora: 20_000
};
async function withinSourceBudget(promise, milliseconds = 7500) {
    let timer;
    try {
        return await Promise.race([
            promise,
            new Promise((_, reject)=>{
                timer = setTimeout(()=>reject(new Error("SOURCE_TIMEOUT")), milliseconds);
            })
        ]);
    } finally{
        if (timer) clearTimeout(timer);
    }
}
function saudiDayKey(timestamp) {
    return new Date(timestamp + 3 * 60 * 60_000).toISOString().slice(0, 10);
}
function mergeLatestWithHistory(latest, history) {
    const byKey = new Map();
    for (const item of [
        ...history,
        ...latest
    ]){
        const existing = byKey.get(item.key);
        if (!existing) {
            byKey.set(item.key, {
                ...item,
                chapters: [
                    ...item.chapters ?? []
                ]
            });
            continue;
        }
        const chapterMap = new Map();
        for (const chapter of [
            ...existing.chapters ?? [],
            ...item.chapters ?? []
        ]){
            const identity = exactChapterIdentity(chapter);
            const current = chapterMap.get(identity);
            if (!current) {
                chapterMap.set(identity, chapter);
                continue;
            }
            const currentAt = parsePublished(current.publishedAt);
            const candidateAt = parsePublished(chapter.publishedAt);
            if (candidateAt != null && (currentAt == null || candidateAt < currentAt)) {
                chapterMap.set(identity, {
                    ...current,
                    ...chapter,
                    publishedAt: chapter.publishedAt
                });
            }
        }
        byKey.set(item.key, {
            ...existing,
            ...item,
            chapters: [
                ...chapterMap.values()
            ]
        });
    }
    return [
        ...byKey.values()
    ];
}
function groupChapters(group, state, read, now) {
    const trackingRows = state.followed.filter((entry)=>group.items.some((item)=>item.key === entry.mangaId));
    const trackingStartedAt = trackingRows.length ? Math.min(...trackingRows.map((entry)=>entry.trackingStartedAt)) : null;
    const byIdentity = new Map();
    for (const item of group.items){
        for (const chapter of item.chapters ?? []){
            if (chapter.synthetic) continue;
            const release = releaseFor(chapter);
            const number = Number(chapter.number);
            if (!release || !Number.isFinite(number) || release.timestamp > now) continue;
            const identity = exactChapterIdentity(chapter);
            const current = byIdentity.get(identity) ?? [];
            current.push({
                item,
                chapter,
                timestamp: release.timestamp,
                kind: release.kind
            });
            byIdentity.set(identity, current);
        }
    }
    const chapters = [];
    for (const [identity, rawVersions] of byIdentity){
        const bySource = new Map();
        for (const version of rawVersions){
            const current = bySource.get(version.item.key);
            if (!current || version.timestamp < current.timestamp) {
                bySource.set(version.item.key, version);
            }
        }
        const versions = [
            ...bySource.values()
        ];
        const firstReleaseAt = Math.min(...versions.map((version)=>version.timestamp));
        const firstReleaseDay = saudiDayKey(firstReleaseAt);
        const sameDayVersions = versions.filter((version)=>saudiDayKey(version.timestamp) === firstReleaseDay).sort((a, b)=>a.timestamp - b.timestamp || a.item.key.localeCompare(b.item.key));
        for (const version of sameDayVersions){
            const number = Number(version.chapter.number);
            chapters.push({
                identity,
                number,
                title: version.chapter.title || `الفصل ${number}`,
                releaseAt: version.timestamp,
                releaseKind: "published",
                read: read.has(readKey(version.item.key, number)),
                sourceKey: version.item.key,
                sourceLabel: SOURCE_LABELS[version.item.source] ?? version.item.source
            });
        }
    }
    chapters.sort((a, b)=>b.releaseAt - a.releaseAt || b.number - a.number || a.identity.localeCompare(b.identity));
    if (!chapters.length) return null;
    const cover = preferredSourceCover(group.items) ?? group.primary;
    return {
        id: group.id,
        item: {
            ...group.primary,
            cover: cover.cover
        },
        sourceKeys: group.items.map((item)=>item.key),
        trackingStartedAt,
        chapters,
        newestAt: chapters[0].releaseAt
    };
}
function collectReadChecks(groups) {
    const pairs = [];
    const seen = new Set();
    for (const group of groups){
        for (const item of group.items){
            for (const chapter of item.chapters ?? []){
                const number = Number(chapter.number);
                if (!Number.isFinite(number)) continue;
                const key = readKey(item.key, number);
                if (seen.has(key)) continue;
                seen.add(key);
                pairs.push({
                    mangaId: item.key,
                    chapter: number
                });
            }
        }
    }
    return pairs;
}
async function loadNewChapterFeed(page = 1, onProgress) {
    const safePage = Math.max(1, Math.min(20, Math.trunc(page)));
    const sourceTasks = VERIFIED_NEW_FEED_SOURCES.flatMap((source)=>{
        const pagesPerFeedPage = VERIFIED_SOURCE_SCAN_PAGES[source] ?? 1;
        const scanStart = (safePage - 1) * pagesPerFeedPage + 1;
        return Array.from({
            length: pagesPerFeedPage
        }, (_, index)=>({
                source,
                page: scanStart + index
            }));
    });
    const totalSteps = sourceTasks.length + 3;
    let completedSteps = 0;
    const report = (label)=>{
        onProgress?.({
            completed: completedSteps,
            total: totalSteps,
            percent: Math.min(100, Math.round(completedSteps / totalSteps * 100)),
            label
        });
    };
    report("بدء فحص المصادر");
    const personalizationPromise = userDataService.getPersonalizationState().finally(()=>{
        completedSteps += 1;
        report("تم تجهيز حسابك");
    });
    const latestPromise = Promise.allSettled(sourceTasks.map(({ source, page: sourcePage })=>withinSourceBudget(sourceService.recent(source, sourcePage), NEW_SOURCE_BUDGET_MS[source] ?? 7500).finally(()=>{
            completedSteps += 1;
            report("جاري جمع أحدث الفصول");
        })));
    const [state, latestSettled] = await Promise.all([
        personalizationPromise,
        latestPromise
    ]);
    const latestItemsByKey = new Map();
    for (const result of latestSettled){
        if (result.status !== "fulfilled") continue;
        for (const item of result.value.items)latestItemsByKey.set(item.key, item);
    }
    const latestItems = [
        ...latestItemsByKey.values()
    ];
    const hasMore = latestSettled.some((result)=>result.status === "fulfilled" && result.value.hasMore);
    const chapterNumbers = [
        ...new Set(latestItems.flatMap((item)=>(item.chapters ?? []).filter((chapter)=>Boolean(chapter.publishedAt)).map((chapter)=>Number(chapter.number)).filter(Number.isFinite)))
    ];
    let historyItems = [];
    try {
        const history = await withinSourceBudget(sourceService.releaseHistory(chapterNumbers), 7500);
        historyItems = history.items;
    } catch  {}
    completedSteps += 1;
    report("تمت مقارنة الفصول بين المصادر");
    const comparableItems = mergeLatestWithHistory(latestItems, historyItems);
    const latestGroups = mergeSourceItems(comparableItems);
    const readPairs = await userDataService.getReadChapterPairs(collectReadChecks(latestGroups));
    const read = new Set(readPairs.map((entry)=>readKey(entry.mangaId, entry.chapter)));
    completedSteps += 1;
    report("اكتمل التحديث");
    const now = Date.now();
    const groups = latestGroups.map((group)=>groupChapters(group, state, read, now)).filter((group)=>Boolean(group)).sort((a, b)=>b.newestAt - a.newestAt || a.id.localeCompare(b.id));
    const cutoff = now - NEW_CHAPTER_WINDOW_MS;
    const all = groups.map((group)=>({
            ...group,
            chapters: group.chapters.filter((chapter)=>chapter.releaseAt > cutoff).slice(0, MAX_NEW_CHAPTERS_PER_WORK)
        })).filter((group)=>group.chapters.length > 0).map((group)=>({
            ...group,
            newestAt: group.chapters[0].releaseAt
        })).sort((a, b)=>b.newestAt - a.newestAt || a.id.localeCompare(b.id));
    const followed = all.filter((group)=>group.trackingStartedAt != null).map((group)=>({
            ...group,
            chapters: group.chapters.filter((chapter)=>chapter.releaseAt > Number(group.trackingStartedAt) && !chapter.read)
        })).filter((group)=>group.chapters.length > 0).sort((a, b)=>b.chapters[0].releaseAt - a.chapters[0].releaseAt || a.id.localeCompare(b.id));
    return {
        followed,
        all,
        unreadFollowedCount: followed.reduce((sum, group)=>sum + group.chapters.filter((chapter)=>!chapter.read).length, 0),
        hasMore,
        page: safePage
    };
}

return {loadNewChapterFeed};
})();
async function runFeed(kind, data, userId, page, runId) {
 try { const report = p => nativeProgress(runId, JSON.stringify(p)); const value = kind === 'fyp' ? await fypEngine.buildFyp(data,userId,report) : await newEngine.loadNewChapterFeed(page,report); nativeResult(runId,JSON.stringify(value),''); } catch(e) { nativeResult(runId,'',String(e.message || e)); }
}
