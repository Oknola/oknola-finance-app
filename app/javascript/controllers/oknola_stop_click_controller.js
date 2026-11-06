// Modified by Cardona Labs, LLC, 2026-11-06, AGPL-3.0
import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  stop(event) {
    event.stopPropagation();
  }
}
