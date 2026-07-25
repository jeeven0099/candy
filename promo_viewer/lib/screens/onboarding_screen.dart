import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;

import '../models/user_prefs.dart';
import '../services/auth_service.dart';
import '../services/interaction_service.dart';
import '../services/saved_deals_service.dart';
import '../services/supabase_service.dart';
import '../services/user_prefs_service.dart';
import '../theme/candy_colors.dart';
import 'main_screen.dart';

// ── Limits ────────────────────────────────────────────────────────────────────

const _kMaxCats   = 3;
const _kMaxBrands = 7;
const _kRadiusKey = 'near_me_radius_mi';

// ── Category definitions ──────────────────────────────────────────────────────

class _Cat {
  final String slug;
  final String emoji;
  final String title;
  final String subtitle;
  final List<String> examples;
  const _Cat(this.slug, this.emoji, this.title, this.subtitle, this.examples);
}

const _kCategories = [
  _Cat('food', '🍔', 'Food & Beverages',
      'Eating out, coffee runs, quick meals',
      ['Starbucks', 'Chipotle', "McDonald's", 'Dunkin']),
  _Cat('grocery', '🛒', 'Groceries & Essentials',
      'Groceries, pharmacy, household items',
      ['Kroger', 'H-E-B', 'Target', 'CVS']),
  _Cat('fashion', '👕', 'Clothes & Shoes',
      'Fashion, shoes, activewear, contemporary',
      ['Nike', 'Zara', 'Maje', 'Aritzia']),
  _Cat('luxury', '👜', 'Bags, Jewelry & Accessible Luxury',
      'Coach, Pandora, Tiffany, Dagne Dover, etc.',
      ['Coach', 'Pandora', 'Tiffany & Co.', 'Dagne Dover']),
  _Cat('designer', '✨', 'Designer & Ultra Luxury',
      'Gucci, Prada, Valentino, Bottega Veneta, etc.',
      ['Gucci', 'Prada', 'Bottega Veneta', 'Loewe']),
  _Cat('beauty', '💄', 'Beauty & Personal Care',
      'Makeup, skincare, fragrance, grooming',
      ['Sephora', 'Tatcha', 'Glossier', 'Drunk Elephant']),
  _Cat('entertainment', '🎬', 'Entertainment',
      'Movies, bowling, events, streaming, gaming',
      ['AMC Theatres', 'Topgolf', 'Steam', 'Spotify']),
  _Cat('home', '🏠', 'Home & Kitchen',
      'Furniture, bedding, kitchen, appliances, decor',
      ['IKEA', 'Wayfair', 'Le Creuset', 'West Elm']),
  _Cat('tech', '💻', 'Tech & Audio',
      'Laptops, electronics, smart home, audio',
      ['Best Buy', 'Sonos', 'Dyson', 'Samsung']),
  _Cat('outdoor', '🏕️', 'Outdoor & Fitness',
      'Hiking, camping, fitness equipment, wellness',
      ['REI', "Arc'teryx", 'Osprey', 'Rogue Fitness']),
  _Cat('kids', '🧸', 'Kids & Family',
      'Toys, baby gear, kids clothing, games',
      ['LEGO', 'Carter\'s', 'Hasbro', 'UPPAbaby']),
  _Cat('travel', '✈️', 'Travel & Luggage',
      'Hotels, luggage, airlines, car rental',
      ['Away', 'Marriott', 'Hyatt', 'Samsonite']),
];

// ── Brand → domain map (for logo lookup) ─────────────────────────────────────

const _kBrandDomains = <String, String>{
  // food
  'Starbucks': 'starbucks.com', 'Dunkin': 'dunkindonuts.com',
  'Chipotle': 'chipotle.com', "McDonald's": 'mcdonalds.com',
  'Chick-fil-A': 'chick-fil-a.com', 'Taco Bell': 'tacobell.com',
  'Wingstop': 'wingstop.com', 'Panera Bread': 'panerabread.com',
  "Domino's": 'dominos.com', 'Shake Shack': 'shakeshack.com',
  "Wendy's": 'wendys.com', 'Subway': 'subway.com',
  'Pizza Hut': 'pizzahut.com', 'Sonic Drive-In': 'sonicdrivein.com',
  'Five Guys': 'fiveguys.com', "Arby's": 'arbys.com',
  'Jack in the Box': 'jackinthebox.com', "Jimmy John's": 'jimmyjohns.com',
  "Jersey Mike's": 'jerseymikes.com', 'Buffalo Wild Wings': 'buffalowildwings.com',
  "Applebee's": 'applebees.com', 'IHOP': 'ihop.com',
  "Chili's": 'chilis.com', 'Del Taco': 'deltaco.com',
  "Culver's": 'culvers.com', 'Whataburger': 'whataburger.com',
  'Firehouse Subs': 'firehousesubs.com', 'Noodles & Company': 'noodles.com',
  'Red Robin': 'redrobin.com', 'Olive Garden': 'olivegarden.com',
  'Cracker Barrel': 'crackerbarrel.com', 'Outback Steakhouse': 'outback.com',
  'Panda Express': 'pandaexpress.com', 'Little Caesars': 'littlecaesars.com',
  'Krispy Kreme': 'krispykreme.com', 'Jamba': 'jamba.com',
  'Tropical Smoothie Cafe': 'tropicalsmoothiecafe.com',
  'Baskin-Robbins': 'baskinrobbins.com', 'Qdoba': 'qdoba.com',
  "Moe's Southwest Grill": 'moes.com', "Church's Chicken": 'churchs.com',
  'LongHorn Steakhouse': 'longhornsteakhouse.com', "P.F. Chang's": 'pfchangs.com',
  'Benihana': 'benihana.com', 'Caribou Coffee': 'cariboucoffee.com',
  'Einstein Bros Bagels': 'einsteinbros.com', 'Black Rock Coffee Bar': 'blackrockcoffee.com',
  // grocery
  'Kroger': 'kroger.com', 'Whole Foods Market': 'wholefoods.com',
  'Costco': 'costco.com', 'Target': 'target.com', 'Walmart': 'walmart.com',
  'Aldi': 'aldi.us', 'Publix': 'publix.com', "Trader Joe's": 'traderjoes.com',
  'CVS': 'cvs.com', 'Walgreens': 'walgreens.com',
  'H-E-B': 'heb.com', "Sam's Club": 'samsclub.com', 'Sprouts': 'sprouts.com',
  'Safeway': 'safeway.com', 'Albertsons': 'albertsons.com',
  'Lidl': 'lidl.com', 'Meijer': 'meijer.com', 'Wegmans': 'wegmans.com',
  'Food Lion': 'foodlion.com', 'Giant Food': 'giantfood.com',
  'Stop & Shop': 'stopandshop.com', "BJ's Wholesale Club": 'bjs.com',
  'Vitamin Shoppe': 'vitaminshoppe.com', 'Five Below': 'fivebelow.com',
  'Dollar General': 'dollargeneral.com', 'Bealls': 'beallsflorida.com',
  'Tractor Supply': 'tractorsupply.com', 'Giant Eagle': 'gianteagle.com',
  'Hy-Vee': 'hy-vee.com', 'Fresh Market': 'thefreshmarket.com',
  'Jewel-Osco': 'jewelosco.com', 'Harris Teeter': 'harristeeter.com',
  'ShopRite': 'shoprite.com', 'Ralphs': 'ralphs.com',
  'WinCo Foods': 'wincofoods.com', 'Thrive Market': 'thrivemarket.com',
  'Misfits Market': 'misfitsmarket.com',
  // fashion
  'Nike': 'nike.com', 'H&M': 'hm.com', 'Lululemon': 'lululemon.com',
  'Old Navy': 'oldnavy.com', 'Zara': 'zara.com', 'Uniqlo': 'uniqlo.com',
  'American Eagle': 'ae.com', 'Gap': 'gap.com', 'Adidas': 'adidas.com',
  'Steve Madden': 'stevemadden.com', 'Abercrombie & Fitch': 'abercrombie.com',
  'Hollister': 'hollisterco.com', 'Aerie': 'ae.com',
  'Anthropologie': 'anthropologie.com', 'Banana Republic': 'bananarepublic.com',
  'Athleta': 'athleta.com', 'Madewell': 'madewell.com',
  'Ann Taylor': 'anntaylor.com', 'LOFT': 'loft.com',
  'Talbots': 'talbots.com', "Chico's": 'chicos.com',
  'White House Black Market': 'whitehouseblackmarket.com',
  'PacSun': 'pacsun.com', 'Hot Topic': 'hottopic.com',
  'Nordstrom': 'nordstrom.com', 'Nordstrom Rack': 'nordstromrack.com',
  "Dillard's": 'dillards.com', 'Belk': 'belk.com',
  "Bloomingdale's": 'bloomingdales.com', 'Skechers': 'skechers.com',
  'Puma': 'puma.com', 'Under Armour': 'underarmour.com',
  'Columbia': 'columbia.com', 'Eddie Bauer': 'eddiebauer.com',
  "Lands' End": 'landsend.com', 'L.L.Bean': 'llbean.com',
  'T.J.Maxx': 'tjmaxx.com', 'Marshalls': 'marshalls.com',
  'Fashion Nova': 'fashionnova.com', 'PrettyLittleThing': 'prettylittlething.com',
  'Boohoo': 'boohoo.com', 'Nasty Gal': 'nastygal.com',
  'Aritzia': 'aritzia.com', 'Windsor': 'windsorstore.com',
  'Lucky Brand': 'luckybrand.com', 'Tillys': 'tillys.com',
  'Dr. Martens': 'drmartens.com', 'Merrell': 'merrell.com',
  'Johnston & Murphy': 'johnstonmurphy.com', 'Cole Haan': 'colehaan.com',
  'Nine West': 'ninewest.com', 'Everlane': 'everlane.com',
  'Rainbow Shops': 'rainbowshops.com', 'Rack Room Shoes': 'rackroomshoes.com',
  'Journeys': 'journeys.com', 'Kizik': 'kizik.com',
  'Roxy': 'roxy.com', 'Quiksilver': 'quiksilver.com', 'Volcom': 'volcom.com',
  'Tommy Hilfiger': 'tommy.com', 'Guess': 'guess.com', 'Fossil': 'fossil.com',
  'Lilly Pulitzer': 'lillypulitzer.com', 'Vineyard Vines': 'vineyardvines.com',
  'AllSaints': 'allsaints.com', 'Ted Baker': 'tedbaker.com',
  'Club Monaco': 'clubmonaco.com', 'Brooks Brothers': 'brooksbrothers.com',
  'BCBG': 'bcbg.com', 'Rag & Bone': 'rag-bone.com',
  'Theory': 'theory.com', 'Vince': 'vince.com',
  'Stuart Weitzman': 'stuartweitzman.com', 'Sam Edelman': 'samedelman.com',
  'SHEIN': 'shein.com', 'ASOS': 'asos.com', 'ThredUp': 'thredup.com',
  'Revolve': 'revolve.com', 'Cider': 'shopcider.com', 'Torrid': 'torrid.com',
  'Adore Me': 'adoreme.com', 'Eloquii': 'eloquii.com', 'Showpo': 'showpo.com',
  'Urban Outfitters': 'urbanoutfitters.com', 'Free People': 'freepeople.com',
  'Express': 'express.com', 'J.Crew': 'jcrew.com', 'Lane Bryant': 'lanebryant.com',
  'DSW': 'dsw.com', 'Famous Footwear': 'famousfootwear.com',
  'Foot Locker': 'footlocker.com', 'Champs Sports': 'champssports.com',
  'Finish Line': 'finishline.com', 'JD Sports': 'jdsports.com',
  'Crocs': 'crocs.com', 'Vans': 'vans.com', 'Converse': 'converse.com',
  'UGG': 'ugg.com', 'Reebok': 'reebok.com', 'Hoka': 'hoka.com',
  'Aldo': 'aldoshoes.com', 'Clarks': 'clarks.com', 'Sperry': 'sperry.com',
  'Brooks Running': 'brooksrunning.com', 'Saucony': 'saucony.com',
  'Princess Polly': 'princesspolly.com', 'Naturalizer': 'naturalizer.com',
  'Maje': 'maje.com', 'Sandro': 'sandro-paris.com', 'Reiss': 'reiss.com',
  'COS': 'cos.com', '& Other Stories': 'stories.com',
  'Massimo Dutti': 'massimodutti.com', 'GANNI': 'ganni.com',
  'STAUD': 'staud.clothing', 'Self-Portrait': 'self-portrait.com',
  'Alice + Olivia': 'aliceandolivia.com', 'Veronica Beard': 'veronicabeard.com',
  'FARM Rio': 'farmrio.com', 'Cuyana': 'cuyana.com',
  'FRAME': 'frame-store.com', 'Rails': 'rails.com', 'A.L.C.': 'alcltd.com',
  'Ulla Johnson': 'ullajohnson.com', 'Tibi': 'tibi.com',
  'Nili Lotan': 'nililotan.com', 'Sea New York': 'sea-ny.com',
  'Anine Bing': 'aninebing.com', 'Zadig & Voltaire': 'zadig-et-voltaire.com',
  'Diane von Furstenberg': 'dvf.com', 'L\'Agence': 'lagence.com',
  'Ba&sh': 'ba-sh.com', 'Shopbop': 'shopbop.com', 'FWRD': 'fwrd.com',
  'Zara Man': 'zara.com', 'Forever 21': 'forever21.com',
  'Shoe Carnival': 'shoecarnival.com', 'ModCloth': 'modcloth.com',
  // luxury
  'Coach': 'coach.com', 'Kate Spade': 'katespade.com',
  'Michael Kors': 'michaelkors.com', 'Tory Burch': 'toryburch.com',
  'Kendra Scott': 'kendrascott.com', 'TUMI': 'tumi.com',
  'Vera Bradley': 'verabradley.com', 'Rebecca Minkoff': 'rebeccaminkoff.com',
  'Ralph Lauren': 'ralphlauren.com', 'Calvin Klein': 'calvinklein.us',
  'Pandora': 'pandora.net', 'Swarovski': 'swarovski.com',
  'Monica Vinader': 'monicavinader.com', 'Gorjana': 'gorjana.com',
  'Catbird': 'catbirdnyc.com', 'Brilliant Earth': 'brilliantearth.com',
  'Blue Nile': 'bluenile.com', 'James Allen': 'bluenile.com',
  'David Yurman': 'davidyurman.com', 'Tiffany & Co.': 'tiffany.com',
  'Cartier': 'cartier.com', 'Missoma': 'missoma.com',
  'Ana Luisa': 'analuisa.com', 'Aurate': 'auratenewyork.com',
  'Daniel Wellington': 'danielwellington.com', 'MVMT': 'mvmt.com',
  'Watch Station': 'watchstation.com', 'Jomashop': 'jomashop.com',
  'Hodinkee Shop': 'hodinkee.com', 'Saks OFF 5TH': 'saksoff5th.com',
  'NET-A-PORTER': 'net-a-porter.com', 'Mytheresa': 'mytheresa.com',
  'Farfetch': 'farfetch.com', '24S': '24s.com',
  'Dagne Dover': 'dagnedover.com', 'MZ Wallace': 'mzwallace.com',
  'Strathberry': 'strathberry.com', 'Polene': 'polene-paris.com',
  'DeMellier': 'demellierlondon.com', 'Aspinal of London': 'aspinaloflondon.com',
  'Mark Cross': 'markcross.com', 'Mansur Gavriel': 'mansurgavriel.com',
  'Rebag': 'rebag.com', 'Fashionphile': 'fashionphile.com',
  'Vestiaire Collective': 'vestiairecollective.com',
  'The RealReal': 'therealreal.com', 'StockX': 'stockx.com',
  'GOAT': 'goat.com', 'Grailed': 'grailed.com',
  'What Goes Around Comes Around': 'whatgoesaroundnyc.com',
  'LXRandCo': 'fashionphile.com',
  // designer
  'Gucci': 'gucci.com', 'Prada': 'prada.com', 'Miu Miu': 'miumiu.com',
  'Bottega Veneta': 'bottegaveneta.com', 'Balenciaga': 'balenciaga.com',
  'Valentino': 'valentino.com', 'Chloé': 'chloe.com', 'Loewe': 'loewe.com',
  'Givenchy': 'givenchy.com', 'Alexander McQueen': 'alexandermcqueen.com',
  'Ferragamo': 'ferragamo.com', 'Jimmy Choo': 'jimmychoo.com',
  'Christian Louboutin': 'christianlouboutin.com',
  'Manolo Blahnik': 'manoloblahnik.com', 'Roger Vivier': 'rogervivier.com',
  'Gianvito Rossi': 'gianvitorossi.com', 'Max Mara': 'maxmara.com',
  'Weekend Max Mara': 'weekendmaxmara.com', 'Sportmax': 'sportmax.com',
  'Etro': 'etro.com', 'Marni': 'marni.com', 'Jil Sander': 'jilsander.com',
  'Lemaire': 'lemaire.fr', 'Dries Van Noten': 'driesvannoten.com',
  'Isabel Marant': 'isabelmarant.com', 'Zimmermann': 'zimmermann.com',
  'Oscar de la Renta': 'oscardelarenta.com', 'Carolina Herrera': 'carolinaherrera.com',
  'Marchesa': 'marchesa.com', 'Roksanda': 'roksanda.com',
  'Simone Rocha': 'simonerocha.com', 'Erdem': 'erdem.com',
  'Khaite': 'khaite.com', 'The Row': 'therow.com',
  'Proenza Schouler': 'proenzaschouler.com', 'Altuzarra': 'altuzarra.com',
  'Gabriela Hearst': 'gabrielahearst.com', 'Akris': 'akris.com',
  'St. John': 'stjohnknits.com', 'Mugler': 'mugler.com',
  'Rabanne': 'rabanne.com', 'Courreges': 'courreges.com',
  'Jacquemus': 'jacquemus.com', 'Coperni': 'coperniparis.com',
  'Maison Kitsune': 'maisonkitsune.com', 'AMI Paris': 'amiparis.com',
  'Kenzo': 'kenzo.com', 'Palm Angels': 'palmangels.com',
  'Off-White': 'off---white.com', 'Fear of God': 'fearofgod.com',
  'Stone Island': 'stoneisland.com', 'Moncler': 'moncler.com',
  'Mackage': 'mackage.com', 'Bogner': 'bogner.com',
  'Perfect Moment': 'perfectmoment.com', 'Moose Knuckles': 'mooseknucklescanada.com',
  'Bvlgari': 'bulgari.com', 'Chopard': 'chopard.com',
  'Van Cleef & Arpels': 'vancleefarpels.com', 'Pomellato': 'pomellato.com',
  'Mikimoto': 'mikimotoamerica.com', 'Messika': 'messika.com',
  'Moda Operandi': 'modaoperandi.com', 'LUISAVIAROMA': 'luisaviaroma.com',
  'MR PORTER': 'mrporter.com', 'Toteme': 'toteme-studio.com',
  'Nanushka': 'nanushka.com', 'Acne Studios': 'acnestudios.com',
  'A.P.C.': 'apc-us.com', 'Aquazzura': 'aquazzura.com',
  'Christopher Esber': 'christopheresber.com.au',
  // beauty
  'Ulta Beauty': 'ulta.com', 'Sephora': 'sephora.com',
  'Bath & Body Works': 'bathandbodyworks.com', 'e.l.f. Cosmetics': 'elfcosmetics.com',
  'ColourPop': 'colourpop.com', 'Fenty Beauty': 'fentybeauty.com',
  'The Ordinary': 'theordinary.com', 'NYX Professional Makeup': 'nyxcosmetics.com',
  'Tarte Cosmetics': 'tartecosmetics.com', 'Clinique': 'clinique.com',
  'Dermstore': 'dermstore.com', 'SkinStore': 'skinstore.com',
  'Bluemercury': 'bluemercury.com', 'Space NK': 'spacenk.com',
  'Cult Beauty': 'cultbeauty.com', 'Lookfantastic': 'lookfantastic.com',
  'Glossier': 'glossier.com', 'Drunk Elephant': 'drunkelephant.com',
  'Sunday Riley': 'sundayriley.com', 'Tatcha': 'tatcha.com',
  'La Mer': 'cremedelamer.com', "Kiehl's": 'kiehls.com',
  'Aesop': 'aesop.com', 'Le Labo': 'lelabofragrances.com',
  'Jo Malone': 'jomalone.com', 'Diptyque': 'diptyqueparis.com',
  'Byredo': 'byredo.com', 'Nécessaire': 'necessaire.com',
  'Augustinus Bader': 'augustinusbader.com', "Paula's Choice": 'paulaschoice.com',
  'Supergoop': 'supergoop.com', 'SkinCeuticals': 'skinceuticals.com',
  'La Roche-Posay': 'laroche-posay.us', 'Fresh': 'fresh.com',
  'Caudalie': 'caudalie.com', 'Sol de Janeiro': 'soldejaneiro.com',
  'Charlotte Tilbury': 'charlottetilbury.com', 'Hourglass': 'hourglasscosmetics.com',
  'Pat McGrath Labs': 'patmcgrath.com', 'Dior Beauty': 'dior.com',
  'YSL Beauty': 'yslbeautyus.com', 'Armani Beauty': 'armanibeauty.com',
  'Maison Margiela Fragrances': 'maisonmargiela-fragrances.us',
  'Urban Decay': 'urbandecay.com', 'Too Faced': 'toofaced.com',
  'Benefit Cosmetics': 'benefitcosmetics.com', 'Kylie Cosmetics': 'kyliecosmetics.com',
  'Rare Beauty': 'rarebeauty.com', 'Morphe': 'morphe.com',
  'Milk Makeup': 'milkmakeup.com', 'IL MAKIAGE': 'ilmakiage.com',
  'Sally Beauty': 'sallybeauty.com',
  // entertainment
  'AMC Theatres': 'amctheatres.com', 'Regal Cinemas': 'regmovies.com',
  'Regal': 'regmovies.com', 'Cinemark': 'cinemark.com',
  'Main Event': 'mainevent.com', "Dave & Buster's": 'daveandbusters.com',
  'Topgolf': 'topgolf.com', 'Bowlero': 'bowlero.com',
  'Spotify': 'spotify.com', 'Disney+': 'disneyplus.com',
  'Hulu': 'hulu.com', 'Netflix': 'netflix.com',
  'Peacock': 'peacocktv.com', 'Paramount+': 'paramountplus.com',
  'Max': 'max.com', 'Apple TV+': 'apple.com',
  'Universal Studios': 'universalstudioshollywood.com',
  'Dollywood': 'dollywood.com', 'Great Wolf Lodge': 'greatwolf.com',
  'Sky Zone': 'skyzone.com', 'Pinstripes': 'pinstripes.com',
  // home
  'IKEA': 'ikea.com', 'Home Depot': 'homedepot.com',
  "Lowe's": 'lowes.com', 'Wayfair': 'wayfair.com',
  'Crate & Barrel': 'crateandbarrel.com', 'West Elm': 'westelm.com',
  'Pottery Barn': 'potterybarn.com', 'Bed Bath & Beyond': 'bedbathandbeyond.com',
  'Williams-Sonoma': 'williams-sonoma.com', 'Sur La Table': 'surlatable.com',
  'CB2': 'cb2.com', 'The Container Store': 'containerstore.com',
  'At Home': 'athome.com', 'World Market': 'worldmarket.com',
  'Ashley Furniture': 'ashleyfurniture.com', 'Rooms To Go': 'roomstogo.com',
  'Ethan Allen': 'ethanallen.com', 'Article': 'article.com',
  'Joybird': 'joybird.com', 'La-Z-Boy': 'la-z-boy.com',
  'Herman Miller': 'hermanmiller.com', 'Design Within Reach': 'dwr.com',
  'Overstock': 'overstock.com', 'Burrow': 'burrow.com', 'Lovesac': 'lovesac.com',
  'Floyd': 'floydhome.com', 'Inside Weather': 'insideweather.com',
  'Castlery': 'castlery.com', 'Lulu and Georgia': 'luluandgeorgia.com',
  'Revival': 'revivalrugs.com', 'Ruggable': 'ruggable.com',
  'Boll & Branch': 'bollandbranch.com', 'Coyuchi': 'coyuchi.com',
  'Brooklinen': 'brooklinen.com', 'Parachute': 'parachutehome.com',
  'Casper': 'casper.com', 'Purple': 'purple.com',
  'Tempur-Pedic': 'tempurpedic.com', 'Saatva': 'saatva.com',
  'Avocado Green Mattress': 'avocadogreenmattress.com',
  'Tuft & Needle': 'tuftandneedle.com', 'Eight Sleep': 'eightsleep.com',
  'The Citizenry': 'the-citizenry.com',
  'Le Creuset': 'lecreuset.com', 'Staub': 'zwilling.com',
  'Made In': 'madeincookware.com', 'Our Place': 'fromourplace.com',
  'Caraway': 'carawayhome.com', 'HexClad': 'hexclad.com',
  'Zwilling': 'zwilling.com', 'All-Clad': 'all-clad.com',
  'Ninja': 'ninjakitchen.com', 'Shark': 'sharkclean.com',
  'Cuisinart': 'cuisinart.com', 'KitchenAid': 'kitchenaid.com',
  'Vitamix': 'vitamix.com', 'Breville': 'breville.com',
  'Nespresso': 'nespresso.com', "De'Longhi": 'delonghi.com',
  'Miele': 'mieleusa.com', 'GE Appliances': 'geappliances.com',
  'GE Profile': 'geappliances.com', 'Samsung Appliances': 'samsung.com',
  'LG Appliances': 'lg.com', 'KitchenAid Appliances': 'kitchenaid.com',
  'Whirlpool': 'whirlpool.com', 'Maytag': 'maytag.com',
  'Frigidaire': 'frigidaire.com', 'Bosch': 'bosch-home.com',
  'Fisher & Paykel': 'fisherpaykel.com', 'Cafe Appliances': 'cafeappliances.com',
  'Sub-Zero': 'subzero-wolf.com', 'Wolf': 'subzero-wolf.com',
  'Viking': 'vikingrange.com', 'Thermador': 'thermador.com',
  'Abt': 'abt.com', 'Appliances Connection': 'appliancesconnection.com',
  'HomeGoods': 'homegoods.com', 'Big Lots': 'biglots.com',
  'Floor & Decor': 'flooranddecor.com',
  // tech
  'Amazon': 'amazon.com', 'Best Buy': 'bestbuy.com',
  'Apple': 'apple.com', 'Dell': 'dell.com', 'Microsoft': 'microsoft.com',
  'GameStop': 'gamestop.com', 'B&H Photo': 'bhphotovideo.com',
  'Adorama': 'adorama.com', 'Samsung': 'samsung.com', 'Newegg': 'newegg.com',
  'Micro Center': 'microcenter.com', 'HP': 'hp.com', 'Lenovo': 'lenovo.com',
  'ASUS': 'asus.com', 'Acer': 'acer.com', 'MSI': 'msi.com',
  'Razer': 'razer.com', 'Logitech': 'logitech.com', 'Corsair': 'corsair.com',
  'SteelSeries': 'steelseries.com', 'HyperX': 'hyperx.com',
  'Sony': 'electronics.sony.com', 'LG': 'lg.com',
  'Canon': 'usa.canon.com', 'Nikon': 'nikonusa.com',
  'DJI': 'dji.com', 'Fujifilm': 'fujifilm-x.com', 'Sony Alpha': 'electronics.sony.com',
  'Bose': 'bose.com', 'Sonos': 'sonos.com', 'JBL': 'jbl.com',
  'Bang & Olufsen': 'bang-olufsen.com', 'Bowers & Wilkins': 'bowerswilkins.com',
  'Sennheiser': 'sennheiser-hearing.com', 'KEF': 'kef.com',
  'Klipsch': 'klipsch.com', 'Denon': 'denon.com', 'Marantz': 'marantz.com',
  'Yamaha Audio': 'usa.yamaha.com', 'SVS': 'svsound.com',
  'Audio-Technica': 'audio-technica.com', 'Shure': 'shure.com',
  'Anker': 'anker.com', 'Belkin': 'belkin.com',
  'Western Digital': 'westerndigital.com', 'SanDisk': 'westerndigital.com',
  'Dyson': 'dyson.com', 'iRobot': 'irobot.com', 'Roborock': 'roborock.com',
  'Eufy': 'eufy.com', 'Ring': 'ring.com', 'Arlo': 'arlo.com',
  'Google Nest': 'google.com', 'BenQ': 'benq.com',
  'LG UltraGear': 'lg.com', 'Alienware': 'dell.com',
  'NZXT': 'nzxt.com', 'Turtle Beach': 'turtlebeach.com',
  'Secretlab': 'secretlab.co', 'DXRacer': 'dxracer.com',
  'Peak Design': 'peakdesign.com', 'Moment': 'shopmoment.com',
  'Garmin': 'garmin.com', 'GoPro': 'gopro.com',
  // outdoor & fitness
  'REI': 'rei.com', "Arc'teryx": 'arcteryx.com', 'Osprey': 'osprey.com',
  'Patagonia': 'patagonia.com', 'The North Face': 'thenorthface.com',
  'Backcountry': 'backcountry.com',
  'Moosejaw': 'publiclands.com', 'Public Lands': 'publiclands.com',
  'Snow Peak': 'snowpeak.com', 'Big Agnes': 'bigagnes.com',
  'MSR': 'cascadedesigns.com', 'NEMO Equipment': 'nemoequipment.com',
  'BioLite': 'bioliteenergy.com', 'Jackery': 'jackery.com',
  'Goal Zero': 'goalzero.com', 'EcoFlow': 'ecoflow.com',
  'YETI': 'yeti.com', 'Solo Stove': 'solostove.com',
  'Thule': 'thule.com', 'Yakima': 'yakima.com',
  'Rogue Fitness': 'roguefitness.com', 'REP Fitness': 'repfitness.com',
  'TRX': 'trxtraining.com', 'Concept2': 'concept2.com',
  'Hydrow': 'hydrow.com', 'Tonal': 'tonal.com',
  'Peloton': 'onepeloton.com', 'NordicTrack': 'nordictrack.com',
  'Bowflex': 'bowflex.com', 'Alo Yoga': 'aloyoga.com',
  'Vuori': 'vuoriclothing.com', 'Outdoor Voices': 'outdoorvoices.com',
  'Carbon38': 'carbon38.com', 'Bandier': 'bandier.com',
  'Therabody': 'therabody.com', 'Hyperice': 'hyperice.com',
  'Oura': 'ouraring.com', 'Whoop': 'whoop.com',
  'WW (Weight Watchers)': 'weightwatchers.com', 'Headspace': 'headspace.com',
  'Oura Ring': 'ouraring.com',
  // kids & family
  'LEGO': 'lego.com', 'Mattel': 'mattel.com', 'Hasbro': 'hasbro.com',
  'Fisher-Price': 'mattel.com', 'Melissa & Doug': 'melissaanddoug.com',
  'Hasbro Pulse': 'hasbropulse.com', 'Funko': 'funko.com',
  'TCGplayer': 'tcgplayer.com', 'Lovevery': 'lovevery.com',
  'Nuna': 'nunababy.com', 'UPPAbaby': 'uppababy.com', 'Doona': 'doona.com',
  'Babylist': 'babylist.com', "Carter's": 'carters.com',
  'Hanna Andersson': 'hannaandersson.com', 'Pottery Barn Kids': 'potterybarnkids.com',
  'Crate & Kids': 'crateandbarrel.com', "The Children's Place": 'childrensplace.com',
  'Hobby Lobby': 'hobbylobby.com', 'Michaels': 'michaels.com',
  'JOANN': 'michaels.com',
  // travel & luggage
  'Away': 'awaytravel.com', 'Rimowa': 'rimowa.com',
  'Samsonite': 'samsonite.com', 'Monos': 'monos.com',
  'Briggs & Riley': 'briggs-riley.com', 'BEIS': 'beistravel.com',
  'Travelpro': 'travelpro.com', 'SteamLine Luggage': 'steamlineluggage.com',
  'Carl Friedrik': 'carlfriedrik.com', 'July': 'july.com',
  'Marriott': 'marriott.com', 'Hilton': 'hilton.com',
  'Hyatt': 'hyatt.com', 'IHG': 'ihg.com',
  'Four Seasons': 'fourseasons.com', 'Ritz-Carlton': 'ritzcarlton.com',
  'Fairmont': 'fairmont.com', 'Omni Hotels': 'omnihotels.com',
  'Wyndham Hotels': 'wyndhamhotels.com', 'Choice Hotels': 'choicehotels.com',
  'Hotels.com': 'hotels.com', 'Booking.com': 'booking.com', 'Hopper': 'hopper.com',
  'VRBO': 'vrbo.com', 'Delta Air Lines': 'delta.com',
  'Southwest Airlines': 'southwest.com', 'JetBlue': 'jetblue.com',
  'Frontier Airlines': 'flyfrontier.com',
  'Enterprise': 'enterprise.com', 'Avis': 'avis.com',
  'Alamo': 'alamo.com', 'Budget': 'budget.com',
  'National Car Rental': 'nationalcar.com',
  // automotive & misc
  'Ace Hardware': 'acehardware.com', 'True Value': 'truevalue.com',
  'Harbor Freight': 'harborfreight.com', 'Northern Tool': 'northerntool.com',
  'AutoZone': 'autozone.com', "O'Reilly Auto Parts": 'oreillyauto.com',
  'Advance Auto Parts': 'advanceautoparts.com', 'Pep Boys': 'pepboys.com',
  'Discount Tire': 'discounttire.com', 'Tire Rack': 'tirerack.com',
  'Valvoline': 'valvoline.com', 'Jiffy Lube': 'jiffylube.com',
  'Firestone': 'firestonecompleteautocare.com',
  'DeWalt': 'dewalt.com', 'Milwaukee Tool': 'milwaukeetool.com',
  'Makita': 'makitatools.com', 'Bosch Tools': 'boschtools.com',
  'Ryobi': 'ryobitools.com', 'Stihl': 'stihlusa.com',
  'EGO Power+': 'egopowerplus.com', 'Greenworks': 'greenworkstools.com',
  'Festool': 'festoolusa.com', 'Rockler': 'rockler.com',
  // health & wellness
  'Rite Aid': 'riteaid.com', 'iHerb': 'iherb.com',
  'MyProtein': 'myprotein.com', 'Optimum Nutrition': 'optimumnutrition.com',
  'AG1': 'drinkag1.com', 'Ritual': 'ritual.com', 'Gainful': 'gainful.com',
  'Momentous': 'livemomentous.com', 'Transparent Labs': 'transparentlabs.com',
  'Goli Nutrition': 'goli.com', 'BODi': 'bodi.com',
  'Roman (Ro)': 'ro.co', 'Nurx': 'nurx.com',
  // pets
  'PetSmart': 'petsmart.com', 'Petco': 'petco.com',
  'Chewy': 'chewy.com', '1800PetMeds': '1800petmeds.com',
  "The Farmer's Dog": 'thefarmersdog.com', 'BarkBox': 'bark.co',
  // streaming & subscription
  'Factor': 'factor75.com', 'Green Chef': 'greenchef.com',
  'Hungryroot': 'hungryroot.com',
  'Dollar Shave Club': 'dollarshaveclub.com', 'Manscaped': 'manscaped.com',
  'Function of Beauty': 'functionofbeauty.com', 'Prose': 'prose.com',
  // gaming
  'Steam': 'steampowered.com', 'Epic Games Store': 'epicgames.com',
  'PlayStation': 'playstation.com', 'PlayStation Store': 'direct.playstation.com',
  'Xbox': 'xbox.com', 'Nintendo': 'nintendo.com',
  'Humble Bundle': 'humblebundle.com', 'Green Man Gaming': 'greenmangaming.com',
  'GOG': 'gog.com',
  // misc
  'Mejuri': 'mejuri.com',
  'Hey Harper': 'heyharper.com', 'Sherwin-Williams': 'sherwin-williams.com',
  'Benjamin Moore': 'benjaminmoore.com', 'Behr': 'behr.com',
  'Build.com': 'build.com', 'Yardzen': 'yardzen.com',
  'Shell': 'fuelrewards.com', 'Exxon Mobil': 'exxon.com',
  'NAPA Auto Parts': 'napaonline.com',
};

// ── Brands per category ───────────────────────────────────────────────────────

const _kBrandsByCategory = <String, List<String>>{
  'food': [
    'Starbucks', 'Chipotle', "McDonald's", 'Dunkin', 'Chick-fil-A',
    'Taco Bell', 'Wingstop', 'Panera Bread', "Domino's", 'Shake Shack',
    "Wendy's", 'Subway', 'Pizza Hut', 'Sonic Drive-In', 'Five Guys',
    "Arby's", "Jimmy John's", "Jersey Mike's", 'Buffalo Wild Wings',
    "Applebee's", 'IHOP', "Chili's", 'Whataburger', "Culver's",
    'Panda Express', 'Little Caesars', 'Krispy Kreme', 'Jamba',
    'Baskin-Robbins', 'Olive Garden', 'Cracker Barrel', 'Outback Steakhouse',
    'Benihana', 'Caribou Coffee', 'Einstein Bros Bagels', 'Firehouse Subs',
  ],
  'grocery': [
    'Kroger', 'Whole Foods Market', 'Costco', 'Target', 'Walmart',
    'Aldi', 'Publix', "Trader Joe's", 'CVS', 'Walgreens',
    'H-E-B', "Sam's Club", 'Sprouts', 'Safeway', 'Albertsons',
    'Lidl', 'Meijer', 'Wegmans', 'Food Lion', 'Stop & Shop',
    "BJ's Wholesale Club", 'Vitamin Shoppe', 'Five Below', 'Dollar General',
    'Tractor Supply', 'Thrive Market', 'Misfits Market',
  ],
  'fashion': [
    'Nike', 'Zara', 'H&M', 'Lululemon', 'Adidas', 'Old Navy', 'Uniqlo',
    'Aritzia', 'Maje', 'Sandro', 'GANNI', 'COS', '& Other Stories',
    'Madewell', 'Anthropologie', 'Free People', 'Urban Outfitters',
    'American Eagle', 'Abercrombie & Fitch', 'Hollister', 'Gap',
    'Banana Republic', 'Athleta', 'Ann Taylor', 'LOFT', 'J.Crew',
    'Revolve', 'Shopbop', 'ASOS', 'SHEIN', 'ThredUp', 'Nordstrom',
    'Nordstrom Rack', 'FWRD', 'Ted Baker', 'Club Monaco', 'AllSaints',
    'Rag & Bone', 'Theory', 'Vince', 'Tommy Hilfiger', 'Guess',
    'Reiss', 'Cuyana', 'FARM Rio', 'STAUD', 'Alice + Olivia',
    'Veronica Beard', 'Self-Portrait', 'Massimo Dutti',
    'FRAME', 'Rails', 'Anine Bing', 'Ba&sh', 'Zadig & Voltaire',
    'L\'Agence', 'Diane von Furstenberg', 'Tibi', 'Ulla Johnson',
    'Hoka', 'On', 'Veja', 'Axel Arigato', 'Common Projects', 'Golden Goose',
    'UGG', 'Reebok', 'Puma', 'Dr. Martens', 'Converse', 'Vans', 'Crocs',
    'Steve Madden', 'Cole Haan', 'Sperry', 'Saucony', 'Brooks Running',
    'DSW', 'Foot Locker', 'Journeys', 'Famous Footwear',
    'Torrid', 'Eloquii', 'Lane Bryant', 'Windsor', 'Fashion Nova',
    'Talbots', "Chico's", 'White House Black Market', 'Express',
    'Stuart Weitzman', 'Sam Edelman', 'Koio', 'Aquazzura', 'Larroudé',
    'Margaux', 'Sarah Flint', 'Birdies',
  ],
  'luxury': [
    'Coach', 'Kate Spade', 'Michael Kors', 'Tory Burch', 'Kendra Scott',
    'TUMI', 'Vera Bradley', 'Rebecca Minkoff', 'Ralph Lauren', 'Calvin Klein',
    'Pandora', 'Swarovski', 'Tiffany & Co.', 'David Yurman', 'Cartier',
    'Monica Vinader', 'Gorjana', 'Catbird', 'Missoma', 'Ana Luisa', 'Aurate',
    'Brilliant Earth', 'Blue Nile', 'Daniel Wellington', 'MVMT', 'Jomashop',
    'Mansur Gavriel', 'Dagne Dover', 'MZ Wallace', 'Strathberry', 'Polene',
    'DeMellier', 'Aspinal of London', 'Mark Cross', 'Briggs & Riley',
    'NET-A-PORTER', 'Mytheresa', 'Farfetch', 'Saks OFF 5TH',
    'Rebag', 'Fashionphile', 'Vestiaire Collective', 'The RealReal',
    'StockX', 'GOAT', 'Grailed',
  ],
  'designer': [
    'Gucci', 'Prada', 'Bottega Veneta', 'Loewe', 'Valentino',
    'Balenciaga', 'Givenchy', 'Alexander McQueen', 'Miu Miu', 'Chloé',
    'Ferragamo', 'Jimmy Choo', 'Christian Louboutin', 'Manolo Blahnik',
    'Gianvito Rossi', 'Aquazzura', 'Max Mara', 'Etro', 'Marni', 'Jil Sander',
    'Dries Van Noten', 'Isabel Marant', 'Zimmermann', 'The Row', 'Khaite',
    'Proenza Schouler', 'Altuzarra', 'Acne Studios', 'A.P.C.', 'AMI Paris',
    'Jacquemus', 'Coperni', 'Maison Kitsune', 'Kenzo', 'Toteme', 'Nanushka',
    'Off-White', 'Palm Angels', 'Fear of God', 'Stone Island', 'Moncler',
    'Mackage', 'Oscar de la Renta', 'Carolina Herrera', 'Erdem', 'Lemaire',
    'Roksanda', 'Simone Rocha', 'Gabriela Hearst', 'Akris', 'St. John',
    'Mugler', 'Rabanne', 'Courreges', 'Bvlgari', 'Chopard',
    'Van Cleef & Arpels', 'Pomellato', 'Mikimoto', 'Messika',
    'MR PORTER', 'Moda Operandi', 'LUISAVIAROMA', '24S',
  ],
  'beauty': [
    'Sephora', 'Ulta Beauty', 'Bath & Body Works', 'e.l.f. Cosmetics',
    'Fenty Beauty', 'Glossier', 'Tatcha', 'Drunk Elephant', 'Sunday Riley',
    'ColourPop', 'The Ordinary', 'NYX Professional Makeup', 'Tarte Cosmetics',
    'Clinique', 'La Mer', "Kiehl's", 'Aesop', 'Charlotte Tilbury',
    'Hourglass', 'Pat McGrath Labs', 'Urban Decay', 'Too Faced',
    'Benefit Cosmetics', 'Kylie Cosmetics', 'Rare Beauty', 'Morphe',
    'Milk Makeup', 'IL MAKIAGE', 'Dior Beauty', 'YSL Beauty', 'Armani Beauty',
    "Paula's Choice", 'Supergoop', 'SkinCeuticals', 'La Roche-Posay',
    'Augustinus Bader', 'Bluemercury', 'Space NK', 'Dermstore', 'Lookfantastic',
    'Sol de Janeiro', 'Nécessaire', 'Caudalie', 'Fresh', 'Byredo',
    'Le Labo', 'Diptyque', 'Jo Malone', 'Maison Margiela Fragrances',
    'Sally Beauty',
  ],
  'entertainment': [
    'AMC Theatres', 'Regal Cinemas', 'Cinemark', 'Main Event',
    "Dave & Buster's", 'Topgolf', 'Bowlero', 'Sky Zone', 'Pinstripes',
    'Spotify', 'Disney+', 'Hulu', 'Netflix', 'Peacock', 'Paramount+',
    'Max', 'Apple TV+', 'Steam', 'Epic Games Store', 'PlayStation',
    'Xbox', 'Nintendo', 'Humble Bundle', 'GameStop',
    'Universal Studios', 'Dollywood', 'Great Wolf Lodge',
  ],
  'home': [
    'IKEA', 'Wayfair', 'West Elm', 'Pottery Barn', 'Crate & Barrel',
    'Williams-Sonoma', 'CB2', 'Article', 'Joybird', 'Burrow',
    'Herman Miller', 'Design Within Reach', 'Floyd', 'Inside Weather',
    'Castlery', 'Lulu and Georgia', 'Revival', 'Ruggable',
    'Boll & Branch', 'Brooklinen', 'Parachute', 'Coyuchi',
    'Casper', 'Purple', 'Tempur-Pedic', 'Saatva', 'Avocado Green Mattress',
    'The Citizenry', 'Le Creuset', 'Made In', 'Our Place', 'Caraway',
    'HexClad', 'Zwilling', 'All-Clad', 'Staub', 'Ninja', 'Cuisinart',
    'KitchenAid', 'Vitamix', 'Breville', 'Nespresso', "De'Longhi",
    'GE Appliances', 'Whirlpool', 'Bosch', 'Miele', 'Sub-Zero',
    'Home Depot', 'Bed Bath & Beyond', 'HomeGoods', 'At Home', 'World Market',
    'Overstock', 'Pottery Barn Kids', 'Sur La Table',
  ],
  'tech': [
    'Amazon', 'Best Buy', 'Apple', 'Samsung', 'Dell', 'Microsoft',
    'HP', 'Lenovo', 'ASUS', 'Acer', 'Newegg', 'Micro Center',
    'Sonos', 'Bose', 'Bang & Olufsen', 'Bowers & Wilkins', 'Sennheiser',
    'Klipsch', 'Denon', 'Marantz', 'SVS', 'Audio-Technica', 'Shure',
    'Dyson', 'iRobot', 'Roborock', 'Eufy', 'Ring', 'Arlo', 'Google Nest',
    'Razer', 'Logitech', 'Corsair', 'SteelSeries', 'NZXT',
    'Alienware', 'LG UltraGear', 'BenQ', 'Secretlab',
    'DJI', 'GoPro', 'Fujifilm', 'Sony Alpha', 'Peak Design', 'Moment',
    'Anker', 'Belkin', 'Western Digital', 'B&H Photo', 'Adorama',
    'Garmin',
  ],
  'outdoor': [
    'REI', "Arc'teryx", 'Osprey', 'Patagonia', 'The North Face',
    'Columbia', 'Eddie Bauer', 'Backcountry', 'Public Lands',
    'Snow Peak', 'Big Agnes', 'MSR', 'NEMO Equipment', 'BioLite',
    'YETI', 'Solo Stove', 'Thule', 'Yakima',
    'Jackery', 'Goal Zero', 'EcoFlow',
    'Rogue Fitness', 'REP Fitness', 'TRX', 'Concept2', 'Hydrow', 'Tonal',
    'Peloton', 'NordicTrack', 'Bowflex', 'Alo Yoga', 'Vuori',
    'Outdoor Voices', 'Carbon38', 'Therabody', 'Hyperice',
    'Oura', 'Whoop', 'Headspace',
  ],
  'kids': [
    'LEGO', 'Hasbro', 'Hasbro Pulse', 'Mattel', 'Fisher-Price',
    'Melissa & Doug', 'Funko', 'TCGplayer', 'Lovevery',
    'UPPAbaby', 'Nuna', 'Doona', 'Babylist',
    "Carter's", 'Hanna Andersson', 'Pottery Barn Kids',
    "The Children's Place", 'Crate & Kids',
    'Hobby Lobby', 'Michaels', 'Steam', 'Epic Games Store',
    'Nintendo', 'PlayStation',
  ],
  'travel': [
    'Away', 'Rimowa', 'TUMI', 'Samsonite', 'Monos', 'BEIS',
    'Briggs & Riley', 'Travelpro', 'Carl Friedrik', 'July',
    'SteamLine Luggage',
    'Marriott', 'Hilton', 'Hyatt', 'IHG', 'Four Seasons',
    'Ritz-Carlton', 'Fairmont', 'Omni Hotels', 'Wyndham Hotels',
    'Hotels.com', 'Booking.com', 'Hopper', 'VRBO',
    'Delta Air Lines', 'Southwest Airlines', 'JetBlue', 'Frontier Airlines',
    'Enterprise', 'Avis', 'Alamo', 'National Car Rental',
  ],
};

List<String> _brandsForCategories(Set<String> cats) {
  final seen   = <String>{};
  final result = <String>[];
  for (final cat in _kCategories.map((c) => c.slug)) {
    if (!cats.contains(cat)) continue;
    for (final b in _kBrandsByCategory[cat] ?? []) {
      if (seen.add(b)) result.add(b);
    }
  }
  return result;
}

// ── Deal type definitions ─────────────────────────────────────────────────────

class _DealType {
  final String slug;
  final String emoji;
  final String title;
  final String subtitle;
  const _DealType(this.slug, this.emoji, this.title, this.subtitle);
}

const _kDealTypes = [
  _DealType('free',     '🎁', 'Free items & birthday rewards',
      'Free food, birthday deals, loyalty freebies'),
  _DealType('bogo',     '🔥', 'BOGO deals',
      'Buy one get one free or 50% off'),
  _DealType('discount', '💸', 'Big discounts',
      '30% off or more, major sales'),
  _DealType('nearby',   '📍', 'Nearby deals',
      'Deals within your chosen radius'),
  _DealType('online',   '🛍', 'Online promo codes',
      'Discount codes usable from any device'),
  _DealType('rewards',  '🏷', 'Rewards & member deals',
      'Loyalty program and membership exclusives'),
];

// ── Radius options ────────────────────────────────────────────────────────────

class _Radius {
  final int    miles;
  final String label;
  final String subtitle;
  const _Radius(this.miles, this.label, this.subtitle);
}

const _kRadii = [
  _Radius(1,  '1 mile',   'Walking distance'),
  _Radius(3,  '3 miles',  'Short drive'),
  _Radius(5,  '5 miles',  'Good for most cities'),
  _Radius(10, '10 miles', 'Wider area, great for Houston'),
  _Radius(25, '25 miles', 'Large metro or suburb'),
];

// ─────────────────────────────────────────────────────────────────────────────

class OnboardingScreen extends StatefulWidget {
  /// When true, skip sign-up and start at category selection (editing prefs).
  final bool startAtPreferences;

  const OnboardingScreen({super.key, this.startAtPreferences = false});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  // Page 0: Auth  1: Categories  2: Brands  3: Deal types  4: Radius
  late final PageController _pageCtrl;

  bool    _isSignIn = false;
  bool    _loading  = false;
  String? _error;

  final _emailCtrl = TextEditingController();
  final _passCtrl  = TextEditingController();
  final _codeCtrl  = TextEditingController();
  bool  _obscure   = true;

  final _selectedCats      = <String>{};
  final _selectedBrands    = <String>{};
  final _selectedDealTypes = <String>{};
  int   _radiusMi          = 5;
  int?  _birthdayMonth;
  int?  _birthdayDay;

  @override
  void initState() {
    super.initState();
    _pageCtrl = PageController(initialPage: widget.startAtPreferences ? 1 : 0);
    if (widget.startAtPreferences) {
      final prefs = UserPrefsService().prefs;
      if (prefs != null) {
        _selectedCats.addAll(prefs.favoriteCategories);
        _selectedBrands.addAll(prefs.favoriteBrands);
        _selectedDealTypes.addAll(prefs.dealPriorities);
        _birthdayMonth = prefs.birthdayMonth;
        _birthdayDay   = prefs.birthdayDay;
      }
      _loadRadius();
    }
  }

  Future<void> _loadRadius() async {
    final sp = await SharedPreferences.getInstance();
    final saved = sp.getInt(_kRadiusKey);
    if (saved != null && mounted) setState(() => _radiusMi = saved);
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  static const _kPageNames = ['auth', 'categories', 'brands', 'deal_types', 'radius'];

  void _goToPage(int p) {
    setState(() => _error = null);
    InteractionService().recordSearchEvent('onboarding_page_viewed',
        params: {'page': p < _kPageNames.length ? _kPageNames[p] : '$p'});
    _pageCtrl.animateToPage(p,
        duration: const Duration(milliseconds: 350), curve: Curves.easeInOut);
  }

  // ── Auth ──────────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    final email = _emailCtrl.text.trim();
    final pass  = _passCtrl.text;
    if (email.isEmpty || pass.isEmpty) {
      setState(() => _error = 'Please fill in all fields.');
      return;
    }
    if (!_isSignIn && _codeCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Please enter your invite code.');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      if (_isSignIn) {
        await AuthService.signIn(email: email, password: pass);
        await UserPrefsService().load();
        final uid = SupabaseService.currentUserId;
        if (uid != null) await SavedDealsService().loadForUser(uid);
        if (mounted) _launchApp();
      } else {
        await AuthService.signUp(
            email: email, password: pass, inviteCode: _codeCtrl.text);
        if (mounted) _goToPage(1);
      }
    } on AuthException catch (e) {
      setState(() => _error = AuthService.friendlyError(e));
    } catch (_) {
      setState(() => _error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _savePrefsAndFinish() async {
    setState(() { _loading = true; _error = null; });

    // Save radius to SharedPreferences (non-fatal)
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setInt(_kRadiusKey, _radiusMi);
    } catch (_) {}

    // Save category/brand/deal prefs to Supabase — show error if it fails
    try {
      await UserPrefsService().save(UserPrefs(
        favoriteCategories: _selectedCats.toList(),
        favoriteBrands:     _selectedBrands.toList(),
        dealPriorities:     _selectedDealTypes.toList(),
        birthdayMonth:      _birthdayMonth,
        birthdayDay:        _birthdayDay,
      ));
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Could not save your preferences. Please check your connection and try again.';
        });
      }
      return;
    }

    // Mark onboarding complete (best-effort, non-fatal)
    if (!widget.startAtPreferences) {
      try {
        final authId = SupabaseService.currentUserId;
        if (authId != null) {
          await SupabaseService.client.from('users').update({
            'onboarding_completed':    true,
            'onboarding_completed_at': DateTime.now().toIso8601String(),
          }).eq('auth_id', authId);
        }
      } catch (_) {}
    }

    if (!mounted) return;
    setState(() => _loading = false);
    if (widget.startAtPreferences) {
      Navigator.of(context).pop();
    } else {
      final uid = SupabaseService.currentUserId;
      if (uid != null) await SavedDealsService().loadForUser(uid);
      _launchApp();
    }
  }

  void _launchApp() => Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const MainScreen()), (_) => false);

  void _toggleCat(String slug) {
    setState(() {
      if (_selectedCats.contains(slug)) {
        _selectedCats.remove(slug);
        final stillValid = _brandsForCategories(_selectedCats).toSet();
        _selectedBrands.removeWhere((b) => !stillValid.contains(b));
      } else if (_selectedCats.length < _kMaxCats) {
        _selectedCats.add(slug);
      }
    });
  }

  void _toggleBrand(String name) => setState(() {
    if (_selectedBrands.contains(name)) {
      _selectedBrands.remove(name);
    } else if (_selectedBrands.length < _kMaxBrands) {
      _selectedBrands.add(name);
    }
  });

  void _toggleDeal(String slug) => setState(() {
    if (_selectedDealTypes.contains(slug)) {
      _selectedDealTypes.remove(slug);
    } else {
      _selectedDealTypes.add(slug);
    }
  });

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Candy.cream,
      body: PageView(
        controller: _pageCtrl,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          _buildAuthPage(),
          _buildCategoriesPage(),
          _buildBrandsPage(),
          _buildDealTypesPage(),
          _buildRadiusPage(),
        ],
      ),
    );
  }

  // ── Page 0: Auth ──────────────────────────────────────────────────────────

  Widget _buildAuthPage() {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(28, 48, 28, 28),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(color: Candy.raspberry,
                  borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.local_offer, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 12),
            const Text('Candy', style: TextStyle(fontSize: 32,
                fontWeight: FontWeight.w800, letterSpacing: -1, color: Candy.chocolate)),
          ]),
          const SizedBox(height: 32),
          Text(_isSignIn ? 'Welcome back' : 'Join the beta',
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700,
                  color: Candy.chocolate, letterSpacing: -0.5)),
          const SizedBox(height: 6),
          Text(
            _isSignIn ? 'Sign in to your Candy account'
                      : 'Discover the best deals around you',
            style: TextStyle(fontSize: 15, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 28),
          _Field(controller: _emailCtrl, label: 'Email',
              hint: 'you@example.com', inputType: TextInputType.emailAddress),
          const SizedBox(height: 14),
          _Field(
            controller: _passCtrl, label: 'Password', hint: '6+ characters',
            obscure: _obscure,
            suffix: IconButton(
              icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility,
                  size: 20, color: Colors.grey),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
          if (!_isSignIn) ...[
            const SizedBox(height: 14),
            _Field(controller: _codeCtrl, label: 'Invite code',
                hint: 'e.g. CANDY2025',
                capitalization: TextCapitalization.characters),
          ],
          if (_error != null) ...[
            const SizedBox(height: 14),
            _ErrorBox(message: _error!),
          ],
          const SizedBox(height: 24),
          _PrimaryButton(label: _isSignIn ? 'Sign In' : 'Join Beta',
              loading: _loading, onTap: _submit),
          const SizedBox(height: 18),
          Center(child: TextButton(
            onPressed: () => setState(() { _isSignIn = !_isSignIn; _error = null; }),
            child: Text(
              _isSignIn ? "Don't have an account? Join Beta"
                        : 'Already have an account? Sign In',
              style: const TextStyle(color: Candy.raspberry, fontWeight: FontWeight.w500),
            ),
          )),
        ]),
      ),
    );
  }

  static const _kMonths = [
    'January','February','March','April','May','June',
    'July','August','September','October','November','December',
  ];

  Widget _birthdayPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Birthday (optional)',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Candy.chocolate),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              flex: 3,
              child: _BirthdayDropdown<int>(
                hint: 'Month',
                value: _birthdayMonth,
                items: List.generate(12, (i) => DropdownMenuItem(
                  value: i + 1,
                  child: Text(_kMonths[i], style: const TextStyle(fontSize: 14)),
                )),
                onChanged: (v) => setState(() => _birthdayMonth = v),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: _BirthdayDropdown<int>(
                hint: 'Day',
                value: _birthdayDay,
                items: List.generate(31, (i) => DropdownMenuItem(
                  value: i + 1,
                  child: Text('${i + 1}', style: const TextStyle(fontSize: 14)),
                )),
                onChanged: (v) => setState(() => _birthdayDay = v),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── Page 1: Categories ────────────────────────────────────────────────────

  Widget _buildCategoriesPage() {
    final count = _selectedCats.length;
    return SafeArea(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _PageHeader(
          step: 1, totalSteps: 4,
          showDots: !widget.startAtPreferences,
          title: 'Make Candy yours',
          subtitle: 'Pick what you usually buy. Candy will show better deals first.\nYou can change this anytime.',
          trailing: widget.startAtPreferences
              ? IconButton(icon: const Icon(Icons.close, color: Candy.chocolate),
                  onPressed: () => Navigator.of(context).pop())
              : const SizedBox.shrink(),
          badge: count == 0 ? 'Pick up to $_kMaxCats'
              : '$count / $_kMaxCats selected',
          badgeHighlight: count == _kMaxCats,
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.88,
            ),
            itemCount: _kCategories.length,
            itemBuilder: (context, i) {
              final cat      = _kCategories[i];
              final sel      = _selectedCats.contains(cat.slug);
              final disabled = !sel && count >= _kMaxCats;
              return _CatGridTile(
                emoji: cat.emoji,
                title: cat.title,
                selected: sel,
                disabled: disabled,
                onTap: disabled ? null : () => _toggleCat(cat.slug),
              );
            },
          ),
        ),
        _BottomActions(
          primaryLabel: 'Continue →',
          primaryEnabled: count > 0,
          onPrimary: count > 0 ? () => _goToPage(2) : null,
          onSkip: () => _goToPage(2),
          loading: false,
        ),
      ]),
    );
  }

  // ── Page 2: Brands ────────────────────────────────────────────────────────

  Widget _buildBrandsPage() {
    final brands = _brandsForCategories(_selectedCats);
    final count  = _selectedBrands.length;
    return SafeArea(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _PageHeader(
          step: 2, totalSteps: 4,
          showDots: !widget.startAtPreferences,
          backOnTap: () => _goToPage(1),
          title: 'Which brands do you care about?',
          subtitle: 'Pick brands you actually shop from, or would buy from if there was a good deal.',
          badge: count == 0 ? 'Pick up to $_kMaxBrands'
              : '$count / $_kMaxBrands selected',
          badgeHighlight: count == _kMaxBrands,
        ),
        Expanded(
          child: brands.isEmpty
              ? Center(child: Text('Select categories first to see brands here.',
                  style: TextStyle(color: Colors.grey.shade500)))
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 5,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 1.0,
                  ),
                  itemCount: brands.length,
                  itemBuilder: (context, i) {
                    final b        = brands[i];
                    final sel      = _selectedBrands.contains(b);
                    final disabled = !sel && count >= _kMaxBrands;
                    return _BrandLogoTile(
                      key: ValueKey(b),
                      brandName: b,
                      domain: _kBrandDomains[b],
                      selected: sel,
                      disabled: disabled,
                      onTap: disabled ? null : () => _toggleBrand(b),
                    );
                  },
                ),
        ),
        _BottomActions(
          primaryLabel: 'Continue →',
          primaryEnabled: true,
          onPrimary: () => _goToPage(3),
          onSkip: () => _goToPage(3),
          loading: false,
        ),
      ]),
    );
  }

  // ── Page 3: Deal types ────────────────────────────────────────────────────

  Widget _buildDealTypesPage() {
    return SafeArea(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _PageHeader(
          step: 3, totalSteps: 4,
          showDots: !widget.startAtPreferences,
          backOnTap: () => _goToPage(2),
          title: 'What kind of deals should Candy prioritize?',
          subtitle: 'Select all that apply. This directly improves your ranking.',
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            itemCount: _kDealTypes.length,
            separatorBuilder: (context, i) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final dt  = _kDealTypes[i];
              final sel = _selectedDealTypes.contains(dt.slug);
              return _SimpleCard(
                emoji: dt.emoji, title: dt.title, subtitle: dt.subtitle,
                selected: sel, onTap: () => _toggleDeal(dt.slug),
              );
            },
          ),
        ),
        _BottomActions(
          primaryLabel: 'Continue →',
          primaryEnabled: true,
          onPrimary: () => _goToPage(4),
          onSkip: () => _goToPage(4),
          loading: false,
        ),
      ]),
    );
  }

  // ── Page 4: Radius ────────────────────────────────────────────────────────

  Widget _buildRadiusPage() {
    return SafeArea(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _PageHeader(
          step: 4, totalSteps: 4,
          showDots: !widget.startAtPreferences,
          backOnTap: () => _goToPage(3),
          title: 'How far should Candy look?',
          subtitle: 'Set the distance for nearby deals. You can always change this in Profile.',
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            itemCount: _kRadii.length,
            separatorBuilder: (context, i) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final r   = _kRadii[i];
              final sel = r.miles == _radiusMi;
              return _SimpleCard(
                emoji: '📍',
                title: r.label,
                subtitle: r.label == '5 miles'
                    ? '${r.subtitle} (default)' : r.subtitle,
                selected: sel,
                onTap: () => setState(() => _radiusMi = r.miles),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Divider(height: 24),
              const Text(
                'Birthday (optional)',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Candy.chocolate),
              ),
              const SizedBox(height: 4),
              Text(
                'Unlock birthday deals from your favourite brands.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
              ),
              const SizedBox(height: 10),
              _birthdayPicker(),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: _PrimaryButton(
            label: widget.startAtPreferences ? 'Save preferences'
                : 'Start discovering deals →',
            loading: _loading,
            onTap: _savePrefsAndFinish,
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared layout components
// ─────────────────────────────────────────────────────────────────────────────

class _PageHeader extends StatelessWidget {
  final int     step;
  final int     totalSteps;
  final bool    showDots;
  final String  title;
  final String  subtitle;
  final String? badge;
  final bool    badgeHighlight;
  final VoidCallback? backOnTap;
  final Widget trailing;

  const _PageHeader({
    required this.step, required this.totalSteps, required this.showDots,
    required this.title, required this.subtitle,
    this.badge, this.badgeHighlight = false,
    this.backOnTap, this.trailing = const SizedBox.shrink(),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (showDots) ...[
          _StepDots(current: step - 1, total: totalSteps),
          const SizedBox(height: 20),
        ],
        Row(children: [
          if (backOnTap != null) ...[
            GestureDetector(
              onTap: backOnTap,
              child: const Icon(Icons.arrow_back_ios_new,
                  size: 18, color: Candy.chocolate),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(child: Text(title,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700,
                  color: Candy.chocolate, letterSpacing: -0.5))),
          trailing,
        ]),
        const SizedBox(height: 6),
        Text(subtitle, style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
        if (badge != null) ...[
          const SizedBox(height: 6),
          Text(badge!,
            style: TextStyle(
              fontSize: 12,
              color: badgeHighlight ? Candy.raspberry : Colors.grey.shade400,
              fontWeight: badgeHighlight ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ],
      ]),
    );
  }
}

class _BottomActions extends StatelessWidget {
  final String       primaryLabel;
  final bool         primaryEnabled;
  final bool         loading;
  final VoidCallback? onPrimary;
  final VoidCallback? onSkip;

  const _BottomActions({
    required this.primaryLabel, required this.primaryEnabled,
    required this.loading, this.onPrimary, this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(children: [
        _PrimaryButton(label: primaryLabel, loading: loading,
            enabled: primaryEnabled, onTap: onPrimary),
        if (onSkip != null) ...[
          const SizedBox(height: 10),
          TextButton(
            onPressed: onSkip,
            child: Text('Skip for now',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
          ),
        ],
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Card widgets
// ─────────────────────────────────────────────────────────────────────────────

class _StepDots extends StatelessWidget {
  final int current;
  final int total;
  const _StepDots({required this.current, required this.total});

  @override
  Widget build(BuildContext context) {
    return Row(children: List.generate(total, (i) {
      final active = i == current;
      return AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(right: 6),
        width: active ? 24 : 8, height: 8,
        decoration: BoxDecoration(
          color: active ? Candy.raspberry : Colors.grey.shade300,
          borderRadius: BorderRadius.circular(4),
        ),
      );
    }));
  }
}

class _CatGridTile extends StatelessWidget {
  final String        emoji;
  final String        title;
  final bool          selected;
  final bool          disabled;
  final VoidCallback? onTap;

  const _CatGridTile({
    required this.emoji, required this.title,
    required this.selected, required this.disabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: selected
              ? Candy.raspberry.withValues(alpha: 0.06)
              : disabled ? Colors.grey.shade50 : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? Candy.raspberry
                : disabled ? Colors.grey.shade100 : Colors.grey.shade200,
            width: selected ? 2.0 : 1.0,
          ),
        ),
        child: Opacity(
          opacity: disabled ? 0.38 : 1.0,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 54, height: 54,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: Text(emoji,
                            style: const TextStyle(fontSize: 28)),
                      ),
                    ),
                    if (selected)
                      Positioned(
                        right: -6, top: -6,
                        child: Container(
                          width: 18, height: 18,
                          decoration: const BoxDecoration(
                            color: Candy.raspberry,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.check,
                              color: Colors.white, size: 12),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 7),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight:
                        selected ? FontWeight.w600 : FontWeight.w500,
                    color:
                        selected ? Candy.raspberry : Candy.chocolate,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SimpleCard extends StatelessWidget {
  final String       emoji;
  final String       title;
  final String       subtitle;
  final bool         selected;
  final VoidCallback onTap;

  const _SimpleCard({
    required this.emoji, required this.title, required this.subtitle,
    required this.selected, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: selected ? Candy.raspberry.withValues(alpha: 0.08) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: selected ? Candy.raspberry : Colors.grey.shade200,
              width: selected ? 1.5 : 1),
        ),
        child: Row(children: [
          Text(emoji, style: const TextStyle(fontSize: 24)),
          const SizedBox(width: 14),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(
                fontSize: 15, fontWeight: FontWeight.w600,
                color: selected ? Candy.raspberry : Candy.chocolate,
              )),
              const SizedBox(height: 2),
              Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
            ],
          )),
          if (selected)
            const Icon(Icons.check_circle, color: Candy.raspberry, size: 20)
          else
            Icon(Icons.circle_outlined, color: Colors.grey.shade300, size: 20),
        ]),
      ),
    );
  }
}

class _BrandLogoTile extends StatefulWidget {
  final String brandName;
  final String? domain;
  final bool selected;
  final bool disabled;
  final VoidCallback? onTap;

  const _BrandLogoTile({
    super.key,
    required this.brandName,
    required this.domain,
    required this.selected,
    required this.disabled,
    required this.onTap,
  });

  @override
  State<_BrandLogoTile> createState() => _BrandLogoTileState();
}

class _BrandLogoTileState extends State<_BrandLogoTile> {
  int _attempt = 0; // 0=local asset  1=icon.horse  2=Google favicon  3=initials

  String get _initials {
    final words = widget.brandName.trim().split(RegExp(r'\s+'));
    if (words.length >= 2) return (words[0][0] + words[1][0]).toUpperCase();
    return widget.brandName
        .substring(0, widget.brandName.length.clamp(0, 2))
        .toUpperCase();
  }

  Color get _avatarColor {
    const colors = [
      Candy.raspberry, Candy.mint, Candy.lavender, Candy.pink,
      Color(0xFF1565C0), Color(0xFFE65100),
    ];
    return colors[widget.brandName.hashCode.abs() % colors.length];
  }

  void _nextAttempt() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _attempt++);
    });
  }

  Widget _shimmer(double size) => Container(
        width: size, height: size,
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(size * 0.2),
        ),
      );

  Widget _initials_(double size) => Container(
        width: size, height: size,
        decoration: BoxDecoration(
          color: _avatarColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(size * 0.2),
        ),
        child: Center(
          child: Text(_initials,
              style: TextStyle(
                color: _avatarColor,
                fontWeight: FontWeight.w700,
                fontSize: size * 0.35,
              )),
        ),
      );

  Widget _logo(double size) {
    final domain = widget.domain;
    if (domain == null || _attempt >= 3) return _initials_(size);

    if (_attempt == 0) {
      return Image.asset(
        'assets/logos/$domain.png',
        width: size, height: size, fit: BoxFit.contain,
        errorBuilder: (_, _, _) {
          _nextAttempt();
          return _shimmer(size);
        },
      );
    }

    final url = _attempt == 1
        ? 'https://icon.horse/icon/$domain'
        : 'https://www.google.com/s2/favicons?domain=$domain&sz=128';
    return Image.network(
      url,
      width: size, height: size, fit: BoxFit.contain,
      errorBuilder: (_, _, _) {
        _nextAttempt();
        return _attempt < 3 ? _shimmer(size) : _initials_(size);
      },
      loadingBuilder: (_, child, loading) =>
          loading == null ? child : _shimmer(size),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: widget.selected
              ? Candy.raspberry.withValues(alpha: 0.06)
              : widget.disabled
                  ? Colors.grey.shade50
                  : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: widget.selected
                ? Candy.raspberry
                : widget.disabled
                    ? Colors.grey.shade100
                    : Colors.grey.shade200,
            width: widget.selected ? 2.0 : 1.0,
          ),
        ),
        child: Opacity(
          opacity: widget.disabled ? 0.38 : 1.0,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final logoSize = constraints.maxWidth * 0.62;
              return Center(
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    _logo(logoSize),
                    if (widget.selected)
                      Positioned(
                        right: -5,
                        top: -5,
                        child: Container(
                          width: 16, height: 16,
                          decoration: const BoxDecoration(
                            color: Candy.raspberry,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.check,
                              color: Colors.white, size: 10),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final String       label;
  final bool         loading;
  final bool         enabled;
  final VoidCallback? onTap;

  const _PrimaryButton({
    required this.label, required this.loading,
    this.enabled = true, this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity, height: 52,
      child: ElevatedButton(
        onPressed: (!enabled || loading) ? null : onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: Candy.raspberry,
          foregroundColor: Colors.white,
          disabledBackgroundColor: Colors.grey.shade200,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 0,
        ),
        child: loading
            ? const SizedBox(width: 20, height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : Text(label,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

class _BirthdayDropdown<T> extends StatelessWidget {
  final String hint;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  const _BirthdayDropdown({
    required this.hint,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      value: value,
      hint: Text(hint, style: TextStyle(color: Colors.grey.shade400, fontSize: 14)),
      items: items,
      onChanged: onChanged,
      isExpanded: true,
      decoration: InputDecoration(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade200)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade200)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Candy.raspberry, width: 1.5)),
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  final String message;
  const _ErrorBox({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(children: [
        Icon(Icons.error_outline, size: 16, color: Colors.red.shade600),
        const SizedBox(width: 8),
        Expanded(child: Text(message,
            style: TextStyle(fontSize: 13, color: Colors.red.shade700))),
      ]),
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final bool   obscure;
  final Widget? suffix;
  final TextInputType      inputType;
  final TextCapitalization capitalization;

  const _Field({
    required this.controller, required this.label, required this.hint,
    this.obscure = false, this.suffix,
    this.inputType = TextInputType.text,
    this.capitalization = TextCapitalization.none,
  });

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 13,
          fontWeight: FontWeight.w600, color: Candy.chocolate)),
      const SizedBox(height: 6),
      TextField(
        controller: controller, obscureText: obscure,
        keyboardType: inputType, textCapitalization: capitalization,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
          suffixIcon: suffix,
          filled: true, fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade200)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade200)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Candy.raspberry, width: 1.5)),
        ),
      ),
    ]);
  }
}
