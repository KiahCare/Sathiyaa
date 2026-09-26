// The languages a carer can say they speak, and a family can search for.
//
// One list, in both apps, for a reason worth stating: the customer app's
// filter and the provider app's picker have to agree, or a family filters for
// a language no carer was ever offered and gets an empty screen. That is not
// hypothetical -- it is close to what was happening, for a worse reason. The
// provider app never asked at all; it sent `languages: ['English']`,
// hardcoded, for every carer who ever registered. The database column, the
// `JSON_CONTAINS` filter in the matching query, the dropdown in the customer
// app and the languages printed on every carer's card were all correct and
// all fed by that one constant. Searching for Hindi returned nobody.
//
// Kept as display names rather than ISO codes because they are shown as
// typed, matched as typed, and stored as typed -- `JSON_CONTAINS(languages,
// JSON_QUOTE('Gujarati'))`. Changing to codes now would orphan every row
// already written.
//
// The order is deliberate: English and Hindi first because they are what most
// carers offer, then the rest alphabetically. Adding one is a one-line change
// here and it appears in both apps at once.
library;

const kLanguages = <String>[
  'English',
  'Hindi',
  'Bengali',
  'Gujarati',
  'Kannada',
  'Malayalam',
  'Marathi',
  'Odia',
  'Punjabi',
  'Tamil',
  'Telugu',
  'Urdu',
];

/// What a new carer starts with ticked.
///
/// English only, and deliberately just one: a pre-ticked list is a list
/// nobody reads, and the whole point of this field is that the carer says
/// what is true rather than accepting what was assumed. English is the one
/// safe guess, and it is one tap to remove.
const kDefaultLanguages = <String>['English'];
