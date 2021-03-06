library(dplyr, warn.conflicts = FALSE)
library(RPostgreSQL)
library(rvest)
library(parallel)

get_index_url <- function(file_name) {
    matches <- stringr::str_match(file_name, "/(\\d+)/(\\d{10}-\\d{2}-\\d{6})")
    cik <- matches[2]
    acc_no <- matches[3]
    path <- stringr::str_replace_all(acc_no, "[^\\d]", "")

    url <- paste0("https://www.sec.gov/Archives/edgar/data/", cik, "/", path, "/",
                  acc_no, "-index.htm")
    return(url)
}

get_filing_docs <- function(file_name) {

    head_url <- get_index_url(file_name)

    table_nodes <-
        read_html(head_url, encoding="Latin1") %>%
        html_nodes("table")

    if (length(table_nodes) < 1) {
        df <- tibble(seq = NA, description = NA, document = NA, type = NA,
                     size = NA, file_name = file_name)
    } else {

        df <-
            table_nodes %>%
            .[[1]] %>%
            html_table() %>%
            mutate(file_name = file_name)

        colnames(df) <- tolower(colnames(df))
    }

    pg <- dbConnect(PostgreSQL())
    dbWriteTable(pg, c("edgar", "filing_docs"),
                 df, append = TRUE, row.names = FALSE)
    dbDisconnect(pg)
    return(TRUE)

}

pg <- dbConnect(PostgreSQL())

filings <- tbl(pg, sql("SELECT * FROM edgar.filings"))

def14_a <-
    filings %>%
    filter(form_type %~% "^6-K")

new_table <- !dbExistsTable(pg, c("edgar", "filing_docs"))

if (!new_table) {
    filing_docs <- tbl(pg, sql("SELECT * FROM edgar.filing_docs"))
    def14_a <- def14_a %>% anti_join(filing_docs)
}

file_names <-
    def14_a %>%
    select(file_name) %>%
    distinct() %>%
    collect()
dbDisconnect(pg)

system.time(temp <- mclapply(file_names$file_name, get_filing_docs, mc.cores=16))

system.time(temp <- lapply(file_names$file_name, get_filing_docs))


if (new_table) {
    pg <- dbConnect(PostgreSQL())
    dbGetQuery(pg, "CREATE INDEX ON edgar.filing_docs (file_name)")
    dbDisconnect(pg)
}

temp <- unlist(temp)
