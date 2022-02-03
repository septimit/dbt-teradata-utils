{# Overriding because the original implementation:  #}
{# - used '=1' test to return boolean. In Teradata it is supported by 'CASE' expression. #}
{# - used '*,' in 'SELECT' statement. In Teradata, '*,' must be qualified with table name. #}

{% macro default__test_mutually_exclusive_ranges(model, lower_bound_column, upper_bound_column, partition_by=None, gaps='allowed', zero_length_range_allowed=False) %}
{% if gaps == 'not_allowed' %}
    {% set allow_gaps_operator='=' %}
    {% set allow_gaps_operator_in_words='equal_to' %}
{% elif gaps == 'allowed' %}
    {% set allow_gaps_operator='<=' %}
    {% set allow_gaps_operator_in_words='less_than_or_equal_to' %}
{% elif gaps == 'required' %}
    {% set allow_gaps_operator='<' %}
    {% set allow_gaps_operator_in_words='less_than' %}
{% else %}
    {{ exceptions.raise_compiler_error(
        "`gaps` argument for mutually_exclusive_ranges test must be one of ['not_allowed', 'allowed', 'required'] Got: '" ~ gaps ~"'.'"
    ) }}
{% endif %}
{% if not zero_length_range_allowed %}
    {% set allow_zero_length_operator='<' %}
    {% set allow_zero_length_operator_in_words='less_than' %}
{% elif zero_length_range_allowed %}
    {% set allow_zero_length_operator='<=' %}
    {% set allow_zero_length_operator_in_words='less_than_or_equal_to' %}
{% else %}
    {{ exceptions.raise_compiler_error(
        "`zero_length_range_allowed` argument for mutually_exclusive_ranges test must be one of [true, false] Got: '" ~ zero_length_range_allowed ~"'.'"
    ) }}
{% endif %}

{% set partition_clause="partition by " ~ partition_by if partition_by else '' %}

with window_functions as (

    select
        {% if partition_by %}
        {{ partition_by }} as partition_by_col,
        {% endif %}
        {{ lower_bound_column }} as lower_bound,
        {{ upper_bound_column }} as upper_bound,

        lead({{ lower_bound_column }}) over (
            {{ partition_clause }}
            order by {{ lower_bound_column }}
        ) as next_lower_bound,

        CASE row_number() over (
            {{ partition_clause }}
	          order by {{ lower_bound_column }} desc
	        )
	        WHEN 1 THEN 1
	        ELSE 0
        END
        as is_last_record

    from {{ model }}

),

calc as (
    -- We want to return records where one of our assumptions fails, so we'll use
    -- the `not` function with `and` statements so we can write our assumptions nore cleanly
    select
        window_functions.*,

        -- For each record: lower_bound should be < upper_bound.
        -- Coalesce it to return an error on the null case (implicit assumption
        -- these columns are not_null)
        coalesce(
             CASE
              WHEN lower_bound IS NULL OR upper_bound IS NULL THEN NULL
            	WHEN lower_bound {{ allow_zero_length_operator }} upper_bound THEN 1
            	ELSE 0
            END,
            0
        ) as lower_bound_{{ allow_zero_length_operator_in_words }}_upper_bound,

        -- For each record: upper_bound {{ allow_gaps_operator }} the next lower_bound.
        -- Coalesce it to handle null cases for the last record.
        coalesce(
            CASE
              WHEN upper_bound IS NULL OR next_lower_bound IS NULL THEN NULL
            	WHEN upper_bound {{ allow_gaps_operator }} next_lower_bound THEN 1
            	ELSE 0
            END,
            is_last_record,
            0
        ) as upper_bound_{{ allow_gaps_operator_in_words }}_next_lower_bound

    from window_functions

),

validation_errors as (

    select
        *
    from calc

    where
        -- THE FOLLOWING SHOULD BE TRUE --
        CASE lower_bound_{{ allow_zero_length_operator_in_words }}_upper_bound + upper_bound_{{ allow_gaps_operator_in_words }}_next_lower_bound
        	WHEN 2 THEN 1
        	ELSE 0
        END = 0

)

select * from validation_errors
{% endmacro %}
