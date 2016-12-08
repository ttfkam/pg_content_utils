-- ===========================================================================
-- content utils PostgreSQL extension
-- Miles Elam <miles@geekspeak.org>
--
-- Depends on file_fdw
--            /usr/share/dict/words (e.g., from apt-get install wamerican-small)
-- ---------------------------------------------------------------------------

-- complain if script is sourced in psql, rather than via CREATE EXTENSION
\echo Use "CREATE EXTENSION content_utils" to load this file. \quit

CREATE SERVER dictionary_word_files
  FOREIGN DATA WRAPPER file_fdw;

CREATE FOREIGN TABLE words_fdt(
    word character varying NULL COLLATE pg_catalog."default")
  SERVER dictionary_word_files
  OPTIONS (filename '/usr/share/dict/words', format 'csv', header 'FALSE');

CREATE MATERIALIZED VIEW words AS
  SELECT DISTINCT lower(words_fdt.word::text) AS word
    FROM words_fdt
  WITH DATA;

CREATE UNIQUE INDEX words_udx ON words USING btree(word);

CREATE FUNCTION count_unusual(input_text text) RETURNS integer
LANGUAGE sql STABLE STRICT LEAKPROOF AS $$
  SELECT count(*)::integer
    FROM (SELECT regexp_split_to_table(lower(input_text || ' '),
                                       '[[:punct:]]*(?:\s+[[:punct:]]*|$)') AS word) AS h
    LEFT JOIN words AS w USING(word)
    WHERE w.word IS NULL;
$$;

CREATE FUNCTION match_unusual(input_text text) RETURNS boolean
LANGUAGE sql STABLE STRICT LEAKPROOF AS $$
  SELECT count(*) > 0
    FROM (SELECT regexp_split_to_table(lower(input_text || ' '),
                                       '[ [:punct:][:digit:]]+') AS word) AS h
    LEFT JOIN words AS w USING(word)
    WHERE w.word IS NULL;
$$;

CREATE FUNCTION rank_modifier(age interval) RETURNS real
LANGUAGE sql IMMUTABLE STRICT LEAKPROOF AS $$
  -- 60 seconds * 60 minutes * 24 hours * 7 days
  SELECT (1 / ceil(extract(epoch from age) / 604800))::real;
$$;

COMMENT ON FUNCTION rank_modifier(age interval) IS
'Older stuff should be less likely to show up in search results.';

CREATE FUNCTION rank_modifier(moment timestamp without time zone DEFAULT now()) RETURNS real
LANGUAGE sql IMMUTABLE STRICT LEAKPROOF AS $$
  SELECT rank_modifier(now() - moment);
$$;

COMMENT ON FUNCTION rank_modifier(moment timestamp without time zone) IS
'Older stuff should be less likely to show up in search results.';

CREATE FUNCTION reify_url(https boolean, url character varying) RETURNS character varying
LANGUAGE sql IMMUTABLE STRICT LEAKPROOF AS $$
  SELECT CASE WHEN https THEN 'https:' ELSE 'http:' END || url;
$$;

COMMENT ON FUNCTION reify_url(https boolean, url character varying) IS 'Add protocol to a URL. This is necessary because we want http and https to be considered equivalent when determining unique headlines.';
