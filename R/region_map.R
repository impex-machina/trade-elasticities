#' R/region_map.R
#'
#' Region mapping: assign exporters to regional aggregates for the regional
#' Stage 2a pass.
#' Extracted from feen94_het_baci.R (lines 59-233) at refactor step 3;
#' content identical to the original, only sectioned.
#'
#' Exported functions:
#'   (see file for the region-mapping definitions and lookups)  — region assignment utilities
#'
#' Depends on: none

# ===========================================================================
#  REGION MAPPING
#
#  Soderbery (2018) Table 1 keeps 13 large countries as individual units
#  and groups remaining countries into 7 regions following UN M49
#  (https://unstats.un.org/unsd/methods/m49/m49regin.htm).
#
#  BACI uses Comtrade numeric country codes. This mapping covers the
#  major trading nations. Unmapped codes are assigned to "OTHER".
#  Users should verify against their BACI country_codes metadata file
#  and adjust as needed.
# ===========================================================================

build_region_map <- function() {

  # --- 13 individual countries (BACI/Comtrade numeric codes) ---
  # Verified against BACI country_codes_V202601.csv
  individual <- data.table(
    cty_code = c(36L, 76L, 124L, 156L, 344L, 446L, 276L, 251L, 826L,
                 699L, 380L, 392L, 484L, 643L, 842L),
    region   = c("AUS","BRA","CAN","CHN","CHN","CHN","DEU","FRA","GBR",
                 "IND","ITA","JPN","MEX","RUS","USA")
  )
  # Notes: 380 = Italy (not 381); 344 = Hong Kong, 446 = Macao → CHN
  #        Historical codes 278/280 (German states) → DEU below

  # --- African (AFR) ---
  afr_codes <- c(
    12L,24L,204L,72L,854L,108L,120L,132L,140L,148L,174L,178L,180L,
    262L,818L,226L,232L,231L,266L,270L,288L,324L,624L,384L,404L,
    426L,430L,434L,450L,454L,466L,478L,480L,504L,508L,516L,562L,
    566L,646L,678L,686L,690L,694L,706L,710L,728L,729L,736L,748L,
    834L,768L,788L,800L,894L,716L,
    # Additional BACI codes
    175L,  # Mayotte
    654L,  # Saint Helena
    711L   # Southern African Customs Union (...1999)
  )

  # --- Asian (ASA, excl CHN/HK/Macao, IND, JPN) ---
  asa_codes <- c(
    4L,48L,50L,64L,96L,104L,116L,360L,364L,368L,376L,400L,398L,
    414L,417L,418L,422L,458L,462L,496L,524L,512L,586L,608L,634L,
    682L,702L,410L,144L,760L,762L,764L,626L,795L,784L,860L,
    704L,887L,
    # Additional BACI codes
    275L,  # State of Palestine
    408L,  # Dem. People's Rep. of Korea
    490L   # Other Asia, nes (includes Taiwan in Comtrade)
  )

  # --- Caribbean (CAR) ---
  car_codes <- c(
    28L,44L,52L,84L,192L,212L,214L,308L,332L,388L,659L,662L,670L,
    740L,780L,535L,
    # Additional BACI codes
    60L,   # Bermuda
    92L,   # British Virgin Islands
    136L,  # Cayman Islands
    500L,  # Montserrat
    530L,  # Netherlands Antilles (...2010)
    531L,  # Curacao
    533L,  # Aruba
    534L,  # Saint Maarten
    652L,  # Saint Barthelemy
    660L,  # Anguilla
    796L   # Turks and Caicos
  )

  # --- Northern/Western Europe (NWU, excl DEU, FRA, GBR) ---
  nwu_codes <- c(
    40L,56L,208L,233L,246L,352L,372L,428L,440L,442L,528L,579L,
    752L,757L,724L,620L,300L,470L,
    # Additional BACI codes
    20L,   # Andorra
    58L,   # Belgium-Luxembourg (...1998)
    292L,  # Gibraltar
    304L,  # Greenland
    666L,  # Saint Pierre and Miquelon
    697L   # Europe EFTA, nes
  )
  # Notes: 579 = Norway (not 578); 757 = Switzerland (not 756)

  # --- Oceania (OCE, excl AUS) ---
  oce_codes <- c(
    554L,598L,242L,90L,882L,776L,548L,583L,584L,585L,520L,
    # Additional BACI codes
    16L,   # American Samoa
    162L,  # Christmas Islands
    166L,  # Cocos Islands
    184L,  # Cook Islands
    258L,  # French Polynesia
    296L,  # Kiribati
    540L,  # New Caledonia
    570L,  # Niue
    574L,  # Norfolk Islands
    580L,  # N. Mariana Islands
    772L,  # Tokelau
    798L,  # Tuvalu
    849L,  # US Misc. Pacific Islands
    876L   # Wallis and Futuna
  )

  # --- South American (SAM, excl BRA, MEX) ---
  sam_codes <- c(
    32L,68L,152L,170L,188L,218L,222L,320L,328L,340L,558L,591L,
    600L,604L,858L,862L,
    # Additional BACI codes
    238L   # Falkland Islands
  )

  # --- Southern/Eastern Europe (SEU, excl ITA, RUS) ---
  seu_codes <- c(
    8L,70L,100L,191L,196L,203L,268L,348L,498L,499L,616L,642L,
    688L,703L,705L,792L,804L,807L,112L,51L,31L,
    # Additional BACI codes
    200L,  # Czechoslovakia (...1992)
    674L,  # San Marino
    891L   # Serbia and Montenegro (...2005)
  )

  # --- Historical German codes → DEU ---
  hist_deu <- data.table(
    cty_code = c(278L, 280L),  # Dem. Rep. / Fed. Rep. of Germany (...1990)
    region   = c("DEU", "DEU")
  )

  regions <- rbindlist(list(
    data.table(cty_code = afr_codes, region = "AFR"),
    data.table(cty_code = asa_codes, region = "ASA"),
    data.table(cty_code = car_codes, region = "CAR"),
    data.table(cty_code = nwu_codes, region = "NWU"),
    data.table(cty_code = oce_codes, region = "OCE"),
    data.table(cty_code = sam_codes, region = "SAM"),
    data.table(cty_code = seu_codes, region = "SEU"),
    hist_deu
  ))

  # Remove any duplicates (a code appearing in both individual + region)
  regions <- regions[!cty_code %in% individual$cty_code]
  regions <- unique(regions, by = "cty_code")

  rbindlist(list(individual, regions))
}


#' Assign regions to a vector of BACI country codes.
#' Unmapped codes are assigned to "OTHER".
#'
#' @param codes Integer or character vector of BACI country codes.
#' @param custom_map Optional data.table with columns (cty_code, region)
#'   to override the built-in mapping.
#' @return Character vector of region labels, same length as codes.
assign_regions <- function(codes, custom_map = NULL) {
  rmap <- if (!is.null(custom_map)) custom_map else build_region_map()
  rmap[, cty_code := as.integer(cty_code)]
  lookup <- data.table(cty_code = as.integer(codes))
  merged <- rmap[lookup, on = "cty_code"]
  merged[is.na(region), region := "OTHER"]
  merged$region
}


# ===========================================================================
#  HS CODE UTILITIES
# ===========================================================================

#' Pad HS6 codes to ensure 6-digit strings with leading zeroes.
#'
#' BACI's product column (k) may be read as numeric by fread/read.csv,
#' which strips leading zeroes (e.g., 010110 -> 10110). This function
#' detects and fixes the issue.
#'
#' @param k Vector of HS6 codes (character or numeric).
#' @return Character vector of 6-digit zero-padded HS6 codes.
