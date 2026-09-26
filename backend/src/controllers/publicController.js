/**
 * The handful of things an app needs to know before anybody has signed in.
 *
 * Right now that is one thing: where Sathiyaa operates. The apps ask for it on
 * the welcome screen so the "we are not in your city yet" page can name the
 * city we ARE in, and so opening a new city does not need a new APK.
 *
 * Behind the shared access key like every other route, but with no bearer
 * token — a person who has not registered yet does not have one, and that is
 * exactly who this is for.
 */
import { asyncHandler } from '../utils/asyncHandler.js';
import { getServiceArea } from '../services/serviceArea.js';

export const serviceArea = asyncHandler(async (req, res) => {
  const area = await getServiceArea();
  res.json({
    enabled: area.enabled,
    city: area.city,
    state: area.state,
    latitude: area.lat,
    longitude: area.lng,
    radiusKm: area.radiusKm,
  });
});
