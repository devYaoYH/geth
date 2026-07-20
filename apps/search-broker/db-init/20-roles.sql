\getenv writer_password SEARCH_AUDIT_DB_WRITER_PASSWORD
\getenv reader_password SEARCH_AUDIT_DB_READER_PASSWORD

CREATE ROLE search_audit_writer LOGIN PASSWORD :'writer_password';
CREATE ROLE search_audit_reader LOGIN PASSWORD :'reader_password';
GRANT USAGE ON SCHEMA public TO search_audit_writer, search_audit_reader;
GRANT SELECT, INSERT, UPDATE ON search_requests, search_results TO search_audit_writer;
GRANT SELECT ON search_requests, search_results TO search_audit_reader;
