library(dplyr, warn.conflicts = FALSE)
library(RPostgreSQL)
library(rvest)

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
    pg <- dbConnect(PostgreSQL())

    head_url <- get_index_url(file_name)

    table_nodes <-
        read_html(head_url) %>%
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

    dbWriteTable(pg, c("edgar", "filing_docs"),
                 df, append = TRUE, row.names = FALSE)
    dbDisconnect(pg)
    return(TRUE)

}

pg <- src_postgres()
filing_docs <- tbl(pg, sql("SELECT * FROM edgar.filing_docs"))
face_output <-
    tbl(pg, sql("SELECT * FROM director_photo.face_output"))
filings <- tbl(pg, sql("SELECT * FROM edgar.filings"))

def14_a <-
    filings %>%
    filter(form_type %~% "^10-K")

file_names <-
    def14_a %>%
    anti_join(filing_docs) %>%
    select(file_name) %>%
    distinct() %>%
    collect()

system.time(temp <- lapply(file_names$file_name[1:10000], get_filing_docs))
unlist(temp)