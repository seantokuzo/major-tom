// Speech bubble text pools — random quips for agent personality

function pick(pool: string[]): string {
  return pool[Math.floor(Math.random() * pool.length)];
}

const TOASTER_FIRE = [
  'Oh shit!!!',
  'FIRE!',
  'Not again...',
  'THE TOASTER!',
  'Call 911!',
  'I smell burning',
  'WHO LEFT THAT ON',
];

const DOG_BARK = [
  'WOOF!',
  'ARF!',
  'BORK!',
  'Woof woof!',
  '*pant pant*',
  'Ruff!',
  'BARK!',
];

const DOG_BEG = [
  '*stares*',
  '*drools*',
  '...food?',
  '*whimper*',
  'pls',
  '*puppy eyes*',
];

const DOG_GENERAL = [
  '*sniff sniff*',
  '*tail wag*',
  '*yawn*',
  'zzz...',
  '*scratch*',
];

const JOB_COMPLETE = [
  'Ship it!',
  'Merged!',
  'Finally done!',
  'LGTM',
  'Deployed!',
  'PR approved!',
  'Done with that shit!',
  'Nailed it',
  '...was that right?',
  'git push!',
];

const PANIC_START = [
  'SHIT!',
  'OH NO!',
  'BOSS IS COMING!',
  'ACT NATURAL!',
  'CTRL+W!',
  'Close Reddit!',
  'LOOK BUSY!',
  'Minimize Slack!',
  'DELETE HISTORY',
  'Hide the memes!',
];

const GENERAL_IDLE = [
  'Need coffee',
  '*yawn*',
  'Is it Friday?',
  'git push --force',
  '...',
  'This is fine',
  'Hm',
  'Monday vibes',
  'Standup in 5',
  'LGTM',
];

const KITCHEN_CHAT = [
  'Smells good',
  'My turn',
  'Nice',
  '*sip*',
  'Decaf? No.',
];

const BREAK_ROOM_CHAT = [
  'Nice shot!',
  'My turn',
  'One more game',
  'Almost...',
  'GG',
];

// ── Social interaction pools ─────────────────────────────

const SOCIAL_INVITE = [
  'Ping pong?',
  'Wanna play?',
  'Game of PP?',
  'Hey, you down?',
  'Quick game?',
  'Challenge you',
];

const SOCIAL_ACCEPT = [
  'Sure!',
  "Let's go!",
  "You're on!",
  'Hell yeah',
  'Down',
  'Ready to lose?',
];

const SOCIAL_DECLINE = [
  'Nah',
  'Maybe later',
  'Pass',
  "I'm good",
  'Too lazy rn',
  'After this...',
];

const PING_PONG_RALLY = [
  'Nice!',
  'Oh!',
  'Take that!',
  'Damn!',
  'Close!',
  'Haha!',
  'Again!',
  '*whiff*',
  'MY POINT!',
  'Ugh',
  'Rematch!',
  'Lucky shot',
  'YOOO',
  'No way',
  'Cheater!',
];

const CASUAL_CHAT = [
  'Hey',
  "What's up",
  'Sup',
  'Busy day huh',
  'Coffee?',
  'You good?',
  'Same tbh',
  'FR',
  'Lol',
  'Heard that',
  'Big mood',
  'Facts',
  'Tell me about it',
  'Ugh, Mondays',
];

export function pickToasterFire(): string { return pick(TOASTER_FIRE); }
export function pickDogBark(): string { return pick(DOG_BARK); }
export function pickDogBeg(): string { return pick(DOG_BEG); }
export function pickDogGeneral(): string { return pick(DOG_GENERAL); }
export function pickJobComplete(): string { return pick(JOB_COMPLETE); }
export function pickPanicStart(): string { return pick(PANIC_START); }
export function pickGeneralIdle(): string { return pick(GENERAL_IDLE); }
export function pickKitchenChat(): string { return pick(KITCHEN_CHAT); }
export function pickBreakRoomChat(): string { return pick(BREAK_ROOM_CHAT); }
export function pickSocialInvite(): string { return pick(SOCIAL_INVITE); }
export function pickSocialAccept(): string { return pick(SOCIAL_ACCEPT); }
export function pickSocialDecline(): string { return pick(SOCIAL_DECLINE); }
export function pickPingPongRally(): string { return pick(PING_PONG_RALLY); }
export function pickCasualChat(): string { return pick(CASUAL_CHAT); }
