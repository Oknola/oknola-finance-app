import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static values = { map: Object };

  connect() {
    this.accountId = null;
    this.pick();
  }

  pick() {
    const account = this.element
      .closest("form")
      .querySelector('[name="entry[account_id]"]');
    const accountId = account?.value;
    if (accountId === this.accountId) return;

    this.accountId = accountId;
    const tagId = this.mapValue[accountId];

    for (const radio of this.element.querySelectorAll('input[type="radio"]')) {
      radio.checked = radio.value === String(tagId);
    }
  }
}
