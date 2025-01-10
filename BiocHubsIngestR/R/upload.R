#' Upload local directory to Bioconductor Hubs Ingest S3 endpoint
#'
#' @param path Character string path to local directory or file to upload
#' @param bucket Character string of bucket name, defaults to "userdata"
#'
#' @return Invisible list of uploaded files
#' @export
#'
#' @examples
#' \dontrun{
#' BiocHubsIngestR::upload("path/to/data")
#' }
upload <- function(path, bucket = "userdata") {
    if (!file.exists(path))
        stop("Path does not exist: ", path)
    
    if (!aws.s3::bucket_exists(bucket)) {
        message("Creating bucket: ", bucket)
        aws.s3::put_bucket(bucket)
    }
    
    if (file.info(path)$isdir) {
        files <- list.files(path, recursive = TRUE, full.names = TRUE)
    } else {
        files <- path
    }
    
    uploaded <- lapply(files, function(f) {
        rel_path <- if(file.info(path)$isdir) {
            sub(paste0("^", path, "/?"), "", f)
        } else {
            basename(f)
        }
        message("Uploading: ", rel_path)
        aws.s3::put_object(
            file = f,
            object = rel_path,
            bucket = bucket
        )
        return(rel_path)
    })
    
    invisible(uploaded)
}
