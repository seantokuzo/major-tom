/** TypeScript declarations for Google Identity Services (GSI) library */

declare namespace google.accounts.id {
  interface CredentialResponse {
    credential: string;
    select_by: string;
  }

  interface GsiButtonConfiguration {
    type?: 'standard' | 'icon';
    theme?: 'outline' | 'filled_blue' | 'filled_black';
    size?: 'large' | 'medium' | 'small';
    text?: 'signin_with' | 'signup_with' | 'continue_with' | 'signin';
    shape?: 'rectangular' | 'pill' | 'circle' | 'square';
    logo_alignment?: 'left' | 'center';
    width?: string | number;
    locale?: string;
  }

  function initialize(config: {
    client_id: string;
    callback: (response: CredentialResponse) => void;
    auto_select?: boolean;
    cancel_on_tap_outside?: boolean;
    context?: 'signin' | 'signup' | 'use';
    itp_support?: boolean;
    login_uri?: string;
    nonce?: string;
    use_fedcm_for_prompt?: boolean;
  }): void;

  function renderButton(
    parent: HTMLElement,
    options: GsiButtonConfiguration,
  ): void;

  function prompt(
    momentListener?: (notification: {
      isDisplayMoment: () => boolean;
      isDisplayed: () => boolean;
      isNotDisplayed: () => boolean;
      getNotDisplayedReason: () => string;
      isSkippedMoment: () => boolean;
      getSkippedReason: () => string;
      isDismissedMoment: () => boolean;
      getDismissedReason: () => string;
    }) => void,
  ): void;

  function disableAutoSelect(): void;
}
