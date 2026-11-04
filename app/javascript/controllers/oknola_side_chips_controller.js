import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static values = { map: Object };

  connect() {
    this.accountId = null;
    if (this.element.querySelector('input[type="radio"]:checked')) {
      this.accountId = this.selectedAccountId();
    } else {
      this.pick();
    }
  }

  pick() {
    const accountId = this.selectedAccountId();
    if (accountId === this.accountId) return;

    this.accountId = accountId;
    const tagId = this.mapValue[accountId];

    for (const radio of this.element.querySelectorAll('input[type="radio"]')) {
      radio.checked = radio.value === String(tagId);
    }
  }

  selectedAccountId() {
    return this.element
      .closest("form")
      .querySelector('[name="entry[account_id]"]')?.value;
  }
}
