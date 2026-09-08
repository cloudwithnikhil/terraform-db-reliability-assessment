-- Deterministic seed data for local assessment.
-- 120 bookings across 4 organizations, 5 cities and 4 statuses.

INSERT INTO hotel_bookings (
    id,
    org_id,
    hotel_id,
    city,
    checkin_date,
    checkout_date,
    amount,
    status,
    created_at
)
SELECT
    gen_random_uuid(),
    ('00000000-0000-0000-0000-' || lpad(((g - 1) % 4 + 1)::text, 12, '0'))::uuid,
    'HOTEL-' || lpad(((g - 1) % 20 + 1)::text, 3, '0'),
    (ARRAY['delhi', 'mumbai', 'bangalore', 'jaipur', 'pune'])[((g - 1) % 5) + 1],
    CURRENT_DATE + ((g % 20) - 10),
    CURRENT_DATE + ((g % 20) - 10) + 2 + (g % 4),
    (120 + (g * 37 % 880))::numeric(12,2),
    (ARRAY['confirmed', 'pending', 'cancelled', 'completed'])[((g - 1) % 4) + 1],
    NOW() - ((g % 45) || ' days')::interval - ((g % 12) || ' hours')::interval
FROM generate_series(1, 120) AS g;

INSERT INTO booking_events (booking_id, event_type, payload, created_at)
SELECT
    hb.id,
    event_data.event_type,
    jsonb_build_object(
        'source', 'seed',
        'booking_id', hb.id,
        'status', hb.status
    ),
    hb.created_at + event_data.offset_value
FROM (
    SELECT
        id,
        status,
        created_at,
        row_number() OVER (ORDER BY created_at, id) AS rn
    FROM hotel_bookings
) hb
CROSS JOIN LATERAL (
    VALUES
        ('booking.created', interval '5 minutes'),
        ('booking.status_changed', interval '2 hours'),
        ('booking.audit', interval '1 day')
) AS event_data(event_type, offset_value)
WHERE hb.rn <= 60;

ANALYZE hotel_bookings;
ANALYZE booking_events;
