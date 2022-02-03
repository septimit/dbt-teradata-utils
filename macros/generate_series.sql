{# Overriding because the original implementation used 'WITH'. Since this query is used in 'date_spine' macro #}
{# which is also 'WITH'-based, it resulted in a nested 'WITH' query which is not supported in Teradata #}

{# only when '*' is qualified with a table/view name #}
{% macro teradata__generate_series(upper_bound) %}
    {{ log("upper_bound : " ~ upper_bound) }}

    {% set n = dbt_utils.get_powers_of_two(upper_bound|trim|int) %}

    select Cast(
    {% for i in range(n) %}
    p{{i}}.generated_number * power(2, {{i}})
    {% if not loop.last %} + {% endif %}
    {% endfor %}
    + 1
    as integer) as gen_number

    from

    {% for i in range(n) %}
    (SELECT * FROM ( SELECT 0 AS generated_number ) t
        UNION ALL
        SELECT * FROM ( SELECT 1 AS generated_number ) t) as p{{i}}
    {% if not loop.last %} cross join {% endif %}
    {% endfor %}


    where gen_number <= {{upper_bound}}

{% endmacro %}
