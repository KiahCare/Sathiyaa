import { query } from '../db/pool.js';
import { asyncHandler } from '../utils/asyncHandler.js';
import { Errors } from '../utils/apiError.js';
import { findMatchingProviders } from '../services/providerMatching.js';
import { getConfigNumber } from '../services/appConfig.js';

export const searchProviders = asyncHandler(async (req, res) => {
  const q = req.query;
  if (!q.service_type || !q.date_from) {
    throw Errors.badRequest('VALIDATION', 'service_type and date_from are required');
  }
  const providers = await findMatchingProviders({
    serviceType: q.service_type,
    dateFrom: q.date_from,
    dateTo: q.date_to || q.date_from,
    // A missing time window means "any time that day", not "every hour of that
    // day". Defaulting to 00:00-23:59 asked for providers whose work hours
    // span the full twenty-four, which is nobody, so leaving the times off
    // returned an empty list instead of a wider one. The apps always send a
    // window; this is for anything calling the API directly.
    timeFrom: q.time_from || undefined,
    timeTo: q.time_to || undefined,
    lat: q.lat !== undefined ? Number(q.lat) : undefined,
    lng: q.lng !== undefined ? Number(q.lng) : undefined,
    radiusKm: q.radius_km !== undefined ? Number(q.radius_km) : undefined,
    gender: q.gender || undefined,
    language: q.language || undefined,
  });

  // What the family will actually be charged.
  //
  // For a freelancer that is their hourly rate, and always was. For an
  // organisation it is the agency's fee plus Sathiyaa's revenue share, and
  // the share was applied only at the end of the visit -- so the card
  // somebody chose from said 100/hr and the bill said 120/hr, with nothing
  // anywhere explaining the difference.
  const orgIds = providers
    .filter((p) => p.provider_kind === 'organization')
    .map((p) => p.provider_id);

  let markupPercent = 0;
  const orgFee = new Map();
  if (orgIds.length > 0) {
    markupPercent = await getConfigNumber('org_revenue_share_percent', 0);
    // The agency's own per-service fee, which overrides the rate on its row.
    // Same precedence computeOrgBilling uses, so the quote and the bill are
    // worked out the same way.
    const overrides = await query(
      `SELECT organization_id, fee_per_hour FROM organization_service_fees
        WHERE service_type = ? AND organization_id IN (${orgIds.map(() => '?').join(',')})`,
      [q.service_type, ...orgIds]
    );
    for (const o of overrides) orgFee.set(Number(o.organization_id), Number(o.fee_per_hour));
  }

  const customerRate = (p) => {
    const base = orgFee.get(Number(p.provider_id)) ?? (Number(p.hourly_rate) || 0);
    if (p.provider_kind !== 'organization') return Number(p.hourly_rate);
    return Math.round(base * (1 + markupPercent / 100) * 100) / 100;
  };

  res.json({
    count: providers.length,
    providers: providers.map((p) => ({
      providerId: p.provider_id,
      displayId: p.display_id,
      name: p.name,
      providerKind: p.provider_kind,
      gender: p.gender,
      photoUrl: p.photo_url,
      ratingAvg: p.rating_avg,
      ratingCount: p.rating_count,
      hourlyRate: customerRate(p),
      yearsExperience: p.years_experience,
      languages: p.languages,
      distanceKm: p.distance_km,
    })),
  });
});

export const getProviderPublicProfile = asyncHandler(async (req, res) => {
  const { id } = req.params;
  const [provider] = await query(
    `SELECT provider_id, display_id, name, provider_kind, gender, photo_url, rating_avg, rating_count, hourly_rate, languages
     FROM service_providers WHERE provider_id = ? AND approval_status = 'approved' AND status = 'active'`,
    [id]
  );
  if (!provider) throw Errors.notFound('Provider not found');
  const expertise = await query('SELECT service_type, years_experience, notes FROM service_provider_expertise WHERE provider_id = ?', [id]);

  res.json({
    providerId: provider.provider_id,
    displayId: provider.display_id,
    name: provider.name,
    providerKind: provider.provider_kind,
    gender: provider.gender,
    photoUrl: provider.photo_url,
    ratingAvg: provider.rating_avg,
    ratingCount: provider.rating_count,
    hourlyRate: provider.hourly_rate,
    languages: provider.languages,
    expertise,
  });
});
